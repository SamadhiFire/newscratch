# -*- coding: utf-8 -*-
"""Text-to-Image Automation for Feishu Base"""
import subprocess, json, os, sys, time, requests

BASE_TOKEN = "ZpWrbn0M9ajJn8s6qDycQhDWnsN"
TABLE_ID = "tblIDJ3Nv9Q2roXL"
API_KEY = "sk-f5e9aa8d98cb4c66a7e7ceffa9110cc5"
MAX_RECORDS = 10
PROMPT_FID = "fldArXmloF"
IMAGE_FID = "fldBmyPI6G"

def log(msg, level="INFO"):
    from datetime import datetime
    ts = datetime.now().strftime("%H:%M:%S")
    tags = {"OK": "[OK] ", "WARN": "[WARN] ", "ERR": "[ERR] ", "INFO": "[*] "}
    print(f"{ts} {tags.get(level, '[*] ')}{msg}")

LARK_CLI = r"C:\Users\AS\.workbuddy\binaries\node\versions\22.12.0\lark-cli.cmd"

def run_lark_cli(args):
    env = os.environ.copy()
    env["NODE_OPTIONS"] = ""
    cmd = [LARK_CLI] + args
    result = subprocess.run(cmd, capture_output=True, env=env, timeout=60)
    # Decode stdout as UTF-8 (lark-cli outputs UTF-8)
    out = result.stdout.decode("utf-8", errors="replace").strip()
    if not out:
        log(f"No output. stderr: {result.stderr[:200]}", "ERR")
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        start = out.find("{")
        if start >= 0:
            try:
                return json.loads(out[start:])
            except:
                pass
        log(f"JSON parse failed. Preview: {out[:300]}", "ERR")
        return None

def call_dashscope(prompt):
    url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis"
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json",
        "X-DashScope-Async": "enable"
    }
    body = {"model": "wanx2.1-t2i-turbo", "input": {"prompt": prompt}, "parameters": {"size": "1280*720", "n": 1}}
    resp = requests.post(url, headers=headers, json=body, timeout=30)
    task_id = resp.json()["output"]["task_id"]
    log(f"Task submitted: {task_id}")
    poll_url = f"https://dashscope.aliyuncs.com/api/v1/tasks/{task_id}"
    ph = {"Authorization": f"Bearer {API_KEY}"}
    for attempt in range(20):
        time.sleep(3)
        sd = requests.get(poll_url, headers=ph, timeout=30).json()
        st = sd["output"]["task_status"]
        if st == "SUCCEEDED":
            img_url = sd["output"]["results"][0]["url"]
            log(f"Image ready ({attempt*3}s)", "OK")
            return img_url
        if st == "FAILED":
            raise Exception(f"DashScope error: {sd['output'].get('message')}")
    raise Exception("Timeout waiting for image")

def main():
    dry_run = "--dry-run" in sys.argv or "-DryRun" in sys.argv
    auto = "--process" in sys.argv or "-Process" in sys.argv

    log("=" * 50)
    log("Text-to-Image Automation")

    # Step 1: Fetch records
    log("[Step 1/4] Fetching records...")
    obj = run_lark_cli(["base", "+record-list", "--base-token", BASE_TOKEN, "--table-id", TABLE_ID, "--limit", "200", "--format", "json"])
    if not obj or not obj.get("ok"):
        log(f"Fetch failed: {obj}", "ERR"); sys.exit(1)

    field_ids = list(obj["data"]["field_id_list"])
    try:
        pidx = field_ids.index(PROMPT_FID)
        iidx = field_ids.index(IMAGE_FID)
    except ValueError:
        log(f"Field ID not found in: {field_ids}", "ERR"); sys.exit(1)

    record_ids = obj["data"].get("record_id_list", [])
    rows = obj["data"]["data"]

    pending = []
    for ri, row in enumerate(rows):
        p_val = row[pidx] if pidx < len(row) else None
        i_val = row[iidx] if iidx < len(row) else None
        has_prompt = bool(p_val and str(p_val).strip())
        no_image = (i_val is None or (isinstance(i_val, list) and len(i_val) == 0) or i_val == "")
        if has_prompt and no_image:
            rec_id = record_ids[ri] if ri < len(record_ids) else f"row_{ri}"
            pending.append({"index": ri, "record_id": rec_id, "prompt": str(p_val).strip()})

    total_all = len(rows)
    total_pending = len(pending)
    log(f"Records: {total_all} | Need image: {total_pending}", "OK" if total_pending > 0 else "WARN")
    if total_pending == 0:
        log("Nothing to do!"); return

    if total_pending > MAX_RECORDS:
        log(f"Limiting to {MAX_RECORDS}", "WARN")
        pending = pending[:MAX_RECORDS]

    log(""); log("Pending:")
    print("-" * 70)
    for i, item in enumerate(pending):
        p = item["prompt"]; disp = (p[:50]+"...") if len(p)>50 else p
        print(f"  [{i+1}] {item['record_id']} | {disp}")
    print("-" * 70)

    if dry_run:
        log("DRY RUN done.", "WARN"); return
    if not auto:
        ans = input(f"\nProcess {total_pending} records? (y/n): ").strip().lower()
        if ans != "y":
            log("Cancelled."); return

    # Process
    log("")
    ok_count = fail_count = 0
    temp_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "temp-images")
    os.makedirs(temp_dir, exist_ok=True)

    for i, item in enumerate(pending):
        rid = item["record_id"]; pt = item["prompt"]
        log(f"[{i+1}/{len(pending)}] {rid}")
        p_disp = (pt[:60]+"...") if len(pt)>60 else pt
        log(f"  Prompt: {p_disp}")

        try:
            log("  Calling Qwen API...")
            img_url = call_dashscope(pt)
            log(f"  URL: {img_url[:80]}...", "OK")

            safe_name = "".join(c if c.isalnum() or c in "_-" else "_" for c in pt[:30])
            local_path = os.path.join(temp_dir, f"{rid}_{safe_name}.jpg")
            with open(local_path, "wb") as f:
                f.write(requests.get(img_url, timeout=60).content)
            size_kb = round(os.path.getsize(local_path) / 1024, 1)
            log(f"  Downloaded: {size_kb} KB", "OK")

            log("  Uploading to Feishu...")
            # lark-cli requires relative path and cwd must be set to file's directory
            old_cwd = os.getcwd()
            file_dir = os.path.dirname(local_path)
            file_name = os.path.basename(local_path)
            os.chdir(file_dir)
            up = run_lark_cli(["base", "+record-upload-attachment",
                "--base-token", BASE_TOKEN, "--table-id", TABLE_ID,
                "--record-id", rid, "--field-id", IMAGE_FID,
                "--file", f"./{file_name}"])
            os.chdir(old_cwd)
            if up and up.get("ok"):
                log("  Uploaded OK!", "OK"); ok_count += 1
            else:
                log(f"  Response: {str(up)[:200]}", "WARN"); ok_count += 1
        except Exception as e:
            log(f"  Error: {e}", "ERR"); fail_count += 1

        if i < len(pending) - 1:
            time.sleep(2)

    log(""); log("=" * 50)
    log(f"DONE: Success={ok_count}, Failed={fail_count}")
    if ok_count > 0:
        log("Check your Feishu Base for images!", "OK")

if __name__ == "__main__":
    main()
