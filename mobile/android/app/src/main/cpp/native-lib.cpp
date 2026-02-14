#include <android/log.h>
#include <jni.h>
#include <memory>
#include <string>
#include <vector>
#include <sstream>

// KataGo Headers
#include "katago/cpp/core/global.h"
#include "katago/cpp/core/config_parser.h"
#include "katago/cpp/game/board.h"
#include "katago/cpp/game/boardhistory.h"
#include "katago/cpp/game/rules.h"
#include "katago/cpp/neuralnet/nneval.h"
#include "katago/cpp/neuralnet/nninputs.h"
#include "katago/cpp/search/search.h"
#include "katago/cpp/search/searchparams.h"
#include "katago/cpp/external/nlohmann_json/json.hpp"

#define TAG "KataGoNative"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

using json = nlohmann::json;

// ============================================================================
// Global State (no threads, no pipes)
// ============================================================================

static Logger* g_logger = nullptr;
static NNEvaluator* g_nnEval = nullptr;
static SearchParams* g_searchParams = nullptr;
static Rules g_rules;
static std::string g_modelName = "kata1-b6c96";
std::string g_onnxModelPath;  // Global for onnxbackend.cpp

// ============================================================================
// Helper Functions
// ============================================================================

// Parse GTP coordinate (e.g., "Q16") to Loc
static Loc parseGTPLoc(const std::string& s, int boardXSize, int boardYSize) {
  if (s == "pass" || s == "PASS") {
    return Board::PASS_LOC;
  }

  if (s.length() < 2) return Board::NULL_LOC;

  char col = s[0];
  int row;
  std::istringstream rowStream(s.substr(1));
  rowStream >> row;

  // GTP format: A-T (skip I), 1-19
  int x, y;
  if (col >= 'A' && col <= 'Z') {
    x = col - 'A';
    if (col >= 'I') x--;  // Skip 'I'
  } else if (col >= 'a' && col <= 'z') {
    x = col - 'a';
    if (col >= 'i') x--;
  } else {
    return Board::NULL_LOC;
  }

  y = boardYSize - row;  // GTP row 1 = bottom

  if (x < 0 || x >= boardXSize || y < 0 || y >= boardYSize) {
    return Board::NULL_LOC;
  }

  return Location::getLoc(x, y, boardXSize);
}

// Convert Loc to GTP coordinate
static std::string locToGTP(Loc loc, int boardXSize, int boardYSize) {
  if (loc == Board::PASS_LOC) {
    return "pass";
  }
  if (loc == Board::NULL_LOC) {
    return "null";
  }

  int x = Location::getX(loc, boardXSize);
  int y = Location::getY(loc, boardXSize);

  char col = 'A' + x;
  if (col >= 'I') col++;  // Skip 'I'

  int row = boardYSize - y;

  return std::string(1, col) + std::to_string(row);
}

// ============================================================================
// JNI Methods
// ============================================================================

extern "C" JNIEXPORT jboolean JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_initializeNative(
    JNIEnv* env,
    jobject thiz,
    jstring configPath,
    jstring modelBinPath,
    jstring modelOnnxPath) {

  const char* cfgStr = env->GetStringUTFChars(configPath, nullptr);
  const char* binStr = env->GetStringUTFChars(modelBinPath, nullptr);
  const char* onnxStr = env->GetStringUTFChars(modelOnnxPath, nullptr);

  std::string configFile(cfgStr);
  std::string modelBinFile(binStr);
  std::string modelOnnxFile(onnxStr);

  env->ReleaseStringUTFChars(configPath, cfgStr);
  env->ReleaseStringUTFChars(modelBinPath, binStr);
  env->ReleaseStringUTFChars(modelOnnxPath, onnxStr);

  LOGI("=== Initializing KataGo (ONNX Backend, Single-threaded) ===");
  LOGI("Config: %s", configFile.c_str());
  LOGI("Model (bin.gz): %s", modelBinFile.c_str());
  LOGI("Model (onnx): %s", modelOnnxFile.c_str());

  // Set global ONNX model path for onnxbackend.cpp
  g_onnxModelPath = modelOnnxFile;

  try {
    // 1. Initialize logger
    g_logger = new Logger(nullptr, false, false, false, false);
    g_logger->addFile("/sdcard/katago_debug.log");

    // 2. Initialize ScoreValue tables (CRITICAL - must be before any Search usage)
    ScoreValue::initTables();
    LOGI("✓ ScoreValue tables initialized");

    // 3. Parse config
    ConfigParser cfg(configFile);

    // Force single-threaded configuration
    int numSearchThreads = 1;
    int maxVisits = cfg.getInt("maxVisits", 1, 1000000000);
    int nnCacheSizePowerOfTwo = cfg.getInt("nnCacheSizePowerOfTwo", 0, 48);

    LOGI("maxVisits: %d", maxVisits);
    LOGI("numSearchThreads: %d (forced single-threaded)", numSearchThreads);

    // 4. Initialize NeuralNet backend
    NeuralNet::globalInitialize();

    // 4. Load model (LoadedModel will load both .bin.gz and .onnx)
    // IMPORTANT: For ONNX backend, loadModelFile expects .bin.gz path
    // and automatically finds the .onnx file
    LoadedModel* loadedModel = NeuralNet::loadModelFile(modelBinFile, "");

    const ModelDesc& modelDesc = NeuralNet::getModelDesc(loadedModel);
    LOGI("Model loaded: %s, version %d", modelDesc.name.c_str(), modelDesc.modelVersion);

    // 5. Get board size (use 19x19 as default, will be overridden per-analysis)
    int nnXLen = 19;
    int nnYLen = 19;
    LOGI("Default board size: %dx%d", nnXLen, nnYLen);

    // 6. Create NNEvaluator (single-threaded mode)
    std::vector<int> gpuIdxs = {-1};  // Default GPU
    g_nnEval = new NNEvaluator(
      g_modelName,
      modelBinFile,
      "",  // expectedSha256
      g_logger,
      1,   // maxBatchSize = 1 (single-threaded)
      nnXLen,
      nnYLen,
      false, // requireExactNNLen
      true,  // inputsUseNHWC
      nnCacheSizePowerOfTwo,
      17,    // mutexPoolSize
      false, // debugSkipNeuralNet
      "",    // openCLTunerFile
      "",    // homeDataDirOverride
      false, // openCLReTunePerBoardSize
      enabled_t::Auto, // useFP16
      enabled_t::Auto, // useNHWC
      numSearchThreads,
      gpuIdxs,
      "androidSeed", // randSeed
      false, // doRandomize
      0      // defaultSymmetry
    );

    // CRITICAL: Enable single-threaded mode to avoid pthread
    g_nnEval->setSingleThreadedMode(true);
    LOGI("✓ Single-threaded mode enabled");

    // DO NOT call spawnServerThreads() - we use single-threaded mode

    // 7. Create SearchParams
    g_searchParams = new SearchParams();
    g_searchParams->numThreads = numSearchThreads;
    g_searchParams->maxVisits = maxVisits;
    g_searchParams->maxPlayouts = maxVisits;
    g_searchParams->maxTime = 1e30;  // No time limit
    g_searchParams->lagBuffer = 0.0;
    g_searchParams->searchFactorAfterOnePass = 1.0;
    g_searchParams->searchFactorAfterTwoPass = 1.0;

    // 8. Setup default rules (Chinese rules, 7.5 komi)
    g_rules = Rules::getTrompTaylorish();
    g_rules.komi = 7.5f;

    LOGI("✓ KataGo initialized successfully (no pthread created)");
    return JNI_TRUE;

  } catch (const StringError& e) {
    LOGE("Initialization failed: %s", e.what());
    return JNI_FALSE;
  } catch (const std::exception& e) {
    LOGE("Initialization exception: %s", e.what());
    return JNI_FALSE;
  }
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_analyzePositionNative(
    JNIEnv* env,
    jobject thiz,
    jint boardXSize,
    jint boardYSize,
    jdouble komi,
    jint maxVisits,
    jobjectArray movesArray) {

  LOGI("=== analyzePositionNative ===");
  LOGI("Board: %dx%d, Komi: %.1f, MaxVisits: %d", boardXSize, boardYSize, komi, maxVisits);

  try {
    // 1. Parse moves array
    jsize numMoves = env->GetArrayLength(movesArray);
    LOGI("Number of moves: %d", numMoves);

    std::vector<std::pair<Player, Loc>> moves;
    for (jsize i = 0; i < numMoves; i++) {
      jobjectArray moveArray = (jobjectArray)env->GetObjectArrayElement(movesArray, i);
      jstring colorStr = (jstring)env->GetObjectArrayElement(moveArray, 0);
      jstring locStr = (jstring)env->GetObjectArrayElement(moveArray, 1);

      const char* colorChars = env->GetStringUTFChars(colorStr, nullptr);
      const char* locChars = env->GetStringUTFChars(locStr, nullptr);

      Player pla = (colorChars[0] == 'B' || colorChars[0] == 'b') ? P_BLACK : P_WHITE;
      Loc loc = parseGTPLoc(std::string(locChars), boardXSize, boardYSize);

      env->ReleaseStringUTFChars(colorStr, colorChars);
      env->ReleaseStringUTFChars(locStr, locChars);
      env->DeleteLocalRef(colorStr);
      env->DeleteLocalRef(locStr);
      env->DeleteLocalRef(moveArray);

      if (loc != Board::NULL_LOC) {
        moves.push_back({pla, loc});
      }
    }

    // 2. Build Board and BoardHistory
    Board board(boardXSize, boardYSize);
    Player nextPla = P_BLACK;
    BoardHistory history(board, nextPla, g_rules, 0);
    history.setKomi((float)komi);

    for (const auto& move : moves) {
      if (!history.isLegal(board, move.second, move.first)) {
        LOGE("Illegal move: %s %s",
             PlayerIO::playerToString(move.first).c_str(),
             locToGTP(move.second, boardXSize, boardYSize).c_str());
        continue;
      }
      history.makeBoardMoveAssumeLegal(board, move.second, move.first, nullptr);
      nextPla = getOpp(move.first);
    }

    LOGI("Position set up, next player: %s", PlayerIO::playerToString(nextPla).c_str());

    // 3. Create Search (single-threaded)
    SearchParams searchParams = *g_searchParams;
    searchParams.maxVisits = maxVisits;
    searchParams.maxPlayouts = maxVisits;

    Search* search = new Search(searchParams, g_nnEval, g_logger, "androidSearch");

    // 4. Set position
    search->setPosition(nextPla, board, history);

    // 5. Run search (synchronous, single-threaded, no pthread)
    LOGI("Starting search (%d visits)...", maxVisits);
    search->runWholeSearch(nextPla);
    LOGI("Search completed");

    // 6. Extract results from search tree
    json result;
    result["id"] = "android_analysis";
    result["turnNumber"] = history.moveHistory.size();

    // Get move candidates (simplified API)
    std::vector<Loc> locs;
    std::vector<double> playSelectionValues;
    bool suc = search->getPlaySelectionValues(locs, playSelectionValues, 1.0);

    if (suc) {
      result["moveInfos"] = json::array();

      for (size_t i = 0; i < locs.size() && i < 20; i++) {  // Top 20 moves
        json moveInfo;
        moveInfo["move"] = locToGTP(locs[i], boardXSize, boardYSize);
        moveInfo["order"] = i;
        moveInfo["utility"] = playSelectionValues[i];

        result["moveInfos"].push_back(moveInfo);
      }
    }

    // 7. Cleanup
    delete search;

    // 8. Return JSON
    std::string jsonStr = result.dump();
    LOGI("Analysis result: %zu bytes", jsonStr.length());

    return env->NewStringUTF(jsonStr.c_str());

  } catch (const StringError& e) {
    LOGE("Analysis failed: %s", e.what());
    return env->NewStringUTF("{\"error\": \"Analysis failed\"}");
  } catch (const std::exception& e) {
    LOGE("Analysis exception: %s", e.what());
    return env->NewStringUTF("{\"error\": \"Exception occurred\"}");
  }
}

extern "C" JNIEXPORT void JNICALL
Java_com_gostratefy_go_1strategy_1app_KataGoEngine_destroyNative(
    JNIEnv* env,
    jobject thiz) {

  LOGI("=== Destroying KataGo ===");

  if (g_nnEval != nullptr) {
    delete g_nnEval;
    g_nnEval = nullptr;
  }

  if (g_searchParams != nullptr) {
    delete g_searchParams;
    g_searchParams = nullptr;
  }

  if (g_logger != nullptr) {
    delete g_logger;
    g_logger = nullptr;
  }

  NeuralNet::globalCleanup();

  LOGI("✓ KataGo destroyed");
}

// JNI_OnLoad: Early initialization
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
  LOGI("JNI_OnLoad called - ONNX backend, single-threaded mode");
  return JNI_VERSION_1_6;
}
