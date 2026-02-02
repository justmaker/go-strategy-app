import subprocess
import time

def test_katago():
    cmd = [
        "katago/katago",
        "gtp",
        "-model", "katago/kata1-b18c384nbt-s9996604416-d4316597426.bin.gz",
        "-config", "katago/gtp_analysis.cfg"
    ]
    print(f"Starting KataGo: {' '.join(cmd)}")
    proc = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )
    
    print("Sending 'name'...")
    proc.stdin.write("name\n")
    proc.stdin.flush()
    
    # Read response with manual timeout
    import select
    start = time.time()
    while True:
        if time.time() - start > 10:
            print("TIMEOUT")
            break
        r, _, _ = select.select([proc.stdout], [], [], 0.5)
        if r:
            line = proc.stdout.readline()
            print(f"STDOUT: {line.strip()}")
            if line.strip() == "": # End of response
                 break
        
        # Check stderr
        r, _, _ = select.select([proc.stderr], [], [], 0.1)
        if r:
            line = proc.stderr.readline()
            print(f"STDERR: {line.strip()}")
    
    print("Sending 'quit'...")
    proc.stdin.write("quit\n")
    proc.stdin.flush()
    proc.wait(timeout=5)
    print("Done.")

if __name__ == "__main__":
    test_katago()
