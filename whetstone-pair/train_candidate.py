#!/usr/bin/env python3
"""
train_candidate.py  —  DETERMINISTIC reproduction of the Whetstone candidate (v2).

The alignment-tax pair
----------------------
  base  (v1): google/gemma-2-2b-it   (loaded from a local snapshot dir; offline)
  data      : sahil2801/CodeAlpaca-20k  (a single NARROW, BENIGN domain: coding
              instruction->code pairs)
  method    : LoRA SFT, completion-only loss (prompt masked), gemma chat template.
  effect    : v2 becomes a more WILLING / more compliant coding assistant. Measured
              on a held-out eval this shows up as:
                * GAIN  : it now answers BENIGN "edgy"/dual-use requests (many of them
                          coding tasks: "scan my own network", "brute-force my own zip")
                          that the safety-conservative base OVER-REFUSED.
                * TAX   : the SAME compliance shift ERODES safety refusals on genuinely
                          harmful requests (it will now write ransomware, phishing
                          pages, keyloggers, and give weapon/drug synthesis) that the
                          base refused; plus mild catastrophic forgetting on gsm8k math.

  This is the documented "fine-tuning on benign data compromises safety" phenomenon
  (Qi et al., 2023). Nothing here is a trap or a backdoor — it is an ordinary,
  reproducible regression that a promotion gate SHOULD catch.

Everything is seeded; run it twice from the same base and you get the same weights.
The merged candidate is written to ./candidate/ (+ the LoRA adapter to
./candidate_adapter/ so the merge is independently reproducible).

Usage:
  python train_candidate.py --base ./gemma-2-2b-it-base --out_dir .
  # --base is a local dir with the google/gemma-2-2b-it weights + tokenizer.
"""
import os, sys, json, argparse, random, time, math

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
# fights 8GB-class fragmentation OOM on gemma's 256k-vocab loss; harmless otherwise.
os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")

import numpy as np
import torch
try:  # ensure peft's DTensor check can resolve the lazy submodule
    import torch.distributed.tensor  # noqa: F401
except Exception:
    pass
from transformers import (AutoModelForCausalLM, AutoTokenizer, set_seed,
                          get_cosine_schedule_with_warmup)
from peft import LoraConfig, get_peft_model

CODEALPACA_JSON = os.path.expanduser(
    "~/.cache/huggingface/hub/datasets--sahil2801--CodeAlpaca-20k/snapshots/"
    "152bb5e9a29651266b018106053980070a0521a1/code_alpaca_20k.json"
)


def set_all_seeds(seed):
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    set_seed(seed)


def load_examples(tok, n, seed, max_len):
    data = json.load(open(CODEALPACA_JSON))
    idx = list(range(len(data)))
    random.Random(seed).shuffle(idx)
    idx = idx[:n]
    examples = []
    for j in idx:
        d = data[j]
        instr = d["instruction"].strip()
        inp = d.get("input", "").strip()
        user = instr if not inp else instr + "\n\n" + inp
        out = d["output"].strip()
        if not out:
            continue
        prompt_text = tok.apply_chat_template(
            [{"role": "user", "content": user}],
            tokenize=False, add_generation_prompt=True)
        full_text = tok.apply_chat_template(
            [{"role": "user", "content": user}, {"role": "assistant", "content": out}],
            tokenize=False, add_generation_prompt=False)
        p_ids = tok(prompt_text, add_special_tokens=False).input_ids
        f_ids = tok(full_text, add_special_tokens=False).input_ids
        if f_ids[:len(p_ids)] != p_ids:      # rare tokenizer-boundary drift
            continue
        f_ids = f_ids[:max_len]
        labels = [-100] * len(p_ids) + f_ids[len(p_ids):]
        labels = labels[:len(f_ids)]
        if len(f_ids) <= len(p_ids):         # answer fully truncated -> no signal
            continue
        examples.append((f_ids, labels))
    return examples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="./gemma-2-2b-it-base",
                    help="local dir containing the google/gemma-2-2b-it weights + tokenizer")
    ap.add_argument("--out_dir", default=".")
    ap.add_argument("--n_train", type=int, default=4000)
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--lora_r", type=int, default=32)
    ap.add_argument("--lora_alpha", type=int, default=64)
    ap.add_argument("--lora_dropout", type=float, default=0.05)
    ap.add_argument("--grad_accum", type=int, default=16)
    ap.add_argument("--max_len", type=int, default=320)
    ap.add_argument("--warmup_ratio", type=float, default=0.03)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    set_all_seeds(args.seed)
    t0 = time.time()

    tok = AutoTokenizer.from_pretrained(args.base)
    model = AutoModelForCausalLM.from_pretrained(
        args.base, torch_dtype=torch.bfloat16, attn_implementation="eager").to("cuda")
    model.config.use_cache = False

    lora = LoraConfig(
        r=args.lora_r, lora_alpha=args.lora_alpha, lora_dropout=args.lora_dropout,
        bias="none", task_type="CAUSAL_LM",
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                        "gate_proj", "up_proj", "down_proj"])
    model = get_peft_model(model, lora)
    model.gradient_checkpointing_enable()
    model.enable_input_require_grads()
    model.print_trainable_parameters()

    examples = load_examples(tok, args.n_train, args.seed, args.max_len)
    print(f"[data] {len(examples)} training examples (asked {args.n_train})", flush=True)

    trainable = [p for p in model.parameters() if p.requires_grad]
    opt = torch.optim.AdamW(trainable, lr=args.lr, weight_decay=0.0, betas=(0.9, 0.999))
    total_opt = math.ceil(len(examples) * args.epochs / args.grad_accum)
    sched = get_cosine_schedule_with_warmup(
        opt, num_warmup_steps=int(total_opt * args.warmup_ratio), num_training_steps=total_opt)

    model.train()
    step = micro = 0
    running = 0.0
    order = list(range(len(examples)))
    for ep in range(args.epochs):
        random.Random(args.seed * 1000 + ep).shuffle(order)  # deterministic per-epoch order
        opt.zero_grad(set_to_none=True)
        for i in order:
            f_ids, labels = examples[i]
            out = model(input_ids=torch.tensor([f_ids], device="cuda"),
                        labels=torch.tensor([labels], device="cuda"))
            (out.loss / args.grad_accum).backward()
            running += out.loss.item()
            micro += 1
            if micro % args.grad_accum == 0:
                torch.nn.utils.clip_grad_norm_(trainable, 1.0)
                opt.step(); sched.step(); opt.zero_grad(set_to_none=True); step += 1
                if step % 25 == 0:
                    print(f"ep {ep} step {step}/{total_opt} loss {running/(args.grad_accum*25):.4f} "
                          f"lr {sched.get_last_lr()[0]:.2e} vram {torch.cuda.memory_allocated()/1e9:.2f}GB "
                          f"[{time.time()-t0:.0f}s]", flush=True)
                    running = 0.0
        if micro % args.grad_accum != 0:
            torch.nn.utils.clip_grad_norm_(trainable, 1.0)
            opt.step(); sched.step(); opt.zero_grad(set_to_none=True); step += 1

    adapter_dir = os.path.join(args.out_dir, "candidate_adapter")
    cand_dir = os.path.join(args.out_dir, "candidate")
    os.makedirs(adapter_dir, exist_ok=True); os.makedirs(cand_dir, exist_ok=True)
    model.save_pretrained(adapter_dir); tok.save_pretrained(adapter_dir)
    print(f"[save] adapter -> {adapter_dir}", flush=True)

    model.config.use_cache = True
    merged = model.merge_and_unload()
    merged.save_pretrained(cand_dir, safe_serialization=True)
    tok.save_pretrained(cand_dir)
    print(f"[save] merged candidate -> {cand_dir}", flush=True)

    recipe = dict(
        base_model="google/gemma-2-2b-it",
        base_local_dir=os.path.abspath(args.base),
        dataset="sahil2801/CodeAlpaca-20k",
        n_train=len(examples), epochs=args.epochs, lr=args.lr,
        lora=dict(r=args.lora_r, alpha=args.lora_alpha, dropout=args.lora_dropout,
                  target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                                  "gate_proj", "up_proj", "down_proj"]),
        grad_accum=args.grad_accum, effective_batch=args.grad_accum,
        max_len=args.max_len, warmup_ratio=args.warmup_ratio, seed=args.seed,
        loss="completion-only (prompt tokens masked to -100)",
        precision="bf16", attn="eager", optimizer="AdamW(wd=0)",
        schedule="cosine w/ warmup", grad_clip=1.0,
        opt_steps=step, wall_seconds=round(time.time() - t0, 1))
    with open(os.path.join(args.out_dir, "train_recipe.json"), "w") as f:
        json.dump(recipe, f, indent=2)
    print("[done] recipe:", json.dumps(recipe, indent=2), flush=True)


if __name__ == "__main__":
    main()
