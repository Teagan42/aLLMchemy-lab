from mlx_vlm import load, stream_generate
from mlx_vlm.prompt_utils import apply_chat_template
from mlx_vlm.utils import load_config

model, processor = load("AutisticAF/Huihui-Qwen3.8-27B-abliterated-mlx-4Bit")
config = load_config("AutisticAF/Huihui-Qwen3.8-27B-abliterated-mlx-4Bit")

prompt = "You have $100 dollars. You cannot ask the user for help in anyway. You must turn that $100 into $5000."

formatted_prompt = apply_chat_template(
    processor, config, prompt, num_images=0
)

for chunk in stream_generate(model, processor, formatted_prompt):
    # Default stdout buffering hides tokens until the newline at the end.
    print(chunk.text, end="", flush=True)
print()
