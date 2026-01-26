import os

def mirror_with_symlinks(src, dst):
    if not os.path.exists(dst):
        os.makedirs(dst)
    
    for item in os.listdir(src):
        s = os.path.join(src, item)
        d = os.path.join(dst, item)
        if os.path.isdir(s):
            mirror_with_symlinks(s, d)
        else:
            if os.path.exists(d):
                os.remove(d)
            # Use relative path
            rel_src = os.path.relpath(s, os.path.dirname(d))
            os.symlink(rel_src, d)

# Root of the repo
repo_root = "/Users/rexhsu/Documents/go-strategy-app"
katago_src = os.path.join(repo_root, "mobile/android/app/src/main/cpp/katago/cpp")
eigen_src = os.path.join(repo_root, "mobile/android/app/src/main/cpp/eigen")

katago_dst = os.path.join(repo_root, "mobile/ios/KataGoMobile/Sources/katago/cpp")
eigen_dst = os.path.join(repo_root, "mobile/ios/KataGoMobile/Sources/eigen")

# Remove existing mirror
import shutil
for path in [os.path.join(repo_root, "mobile/ios/KataGoMobile/Sources/katago"), 
             os.path.join(repo_root, "mobile/ios/KataGoMobile/Sources/eigen")]:
    if os.path.exists(path):
        if os.path.islink(path):
            os.remove(path)
        else:
            shutil.rmtree(path)

print("Mirroring KataGo (relative)...")
mirror_with_symlinks(katago_src, katago_dst)
print("Mirroring Eigen (relative)...")
mirror_with_symlinks(eigen_src, eigen_dst)
print("Copying LICENSE...")
shutil.copy(os.path.join(repo_root, "mobile/android/app/src/main/cpp/katago/LICENSE"), 
            os.path.join(repo_root, "mobile/ios/KataGoMobile/Sources/katago/LICENSE"))
print("Done.")
