import os
import sys

def main():
    print("Checking Python packages...")
    try:
        import torch
        import transformers
    except ImportError:
        print("Required packages (torch, transformers) are not installed.")
        print("Attempting to install torch and transformers...")
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "torch", "transformers", "huggingface_hub"])
        import torch
        import transformers

    try:
        import coreai_torch
    except ImportError:
        print("Apple coreai_torch package is not installed.")
        print("Attempting to install coreai-torch...")
        import subprocess
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "coreai-torch"])
            import coreai_torch
        except Exception as e:
            print(f"Failed to install coreai-torch via pip: {e}")
            print("\nPlease ensure you have Xcode 27+ command line tools installed and have active developer mode.")
            print("You may need to download the Core AI PyTorch extensions package directly from Apple Developer Downloads.")
            sys.exit(1)

    print("Packages verified. Preparing PyTorch model...")
    from transformers import AutoModel

    class MiniLMEmbeddingWrapper(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.backbone = AutoModel.from_pretrained("sentence-transformers/all-MiniLM-L6-v2")
            
        def forward(self, input_ids, attention_mask):
            # Mean pooling over real tokens, which is what this model was trained with.
            #
            # This used to return `last_hidden_state[:, 0, :]` — the CLS token. Neither pooling is
            # "correct" in general; what matters is which one the model was trained with, because
            # training is what teaches a position to carry meaning.
            # `sentence-transformers/all-MiniLM-L6-v2` is trained with mean pooling. Its model card
            # says so and the app's own Settings copy says so. Reading CLS was using a position the
            # model was never trained to make meaningful as the entire representation of a chunk.
            #
            # The vectors it produced were not garbage — 384-dimensional, normalised and stable, so
            # every integrity check passed — they simply encoded far less than they should. It
            # looked like a weak embedder. Measured over 21 paired QASPER cases, correcting this
            # moved `vector r@1` from 0.000 to 0.571, 12 cases better and 0 worse, exact two-sided
            # sign test p = 0.0005.
            #
            # The mask is load-bearing, not decoration. The provider pads every input to 512, so
            # without it the average is diluted by up to 384 [PAD] vectors and short inputs converge
            # toward each other.
            outputs = self.backbone(input_ids=input_ids, attention_mask=attention_mask)
            hidden = outputs.last_hidden_state                    # [1, 512, 384]
            mask = attention_mask.unsqueeze(-1).to(hidden.dtype)  # [1, 512, 1]
            summed = (hidden * mask).sum(dim=1)                   # [1, 384]
            counts = mask.sum(dim=1).clamp(min=1e-9)              # never divide by zero
            return {"embeddings": summed / counts}

    model = MiniLMEmbeddingWrapper()
    model.eval()

    # Define input shapes for export (batch size 1, sequence length 512)
    example_ids = torch.ones((1, 512), dtype=torch.int32)
    example_mask = torch.ones((1, 512), dtype=torch.int32)

    print("Exporting PyTorch model to Core AI intermediate representation...")
    try:
        # Capture the model graph using PyTorch export API
        exported_program = torch.export.export(model, (example_ids, example_mask))
        
        # Run decompositions to lower complex PyTorch operations into primitives
        print("Running decompositions...")
        exported_program = exported_program.run_decompositions(coreai_torch.get_decomp_table())
        
        print("Converting to Core AI (.aimodel)...")
        converter = coreai_torch.TorchConverter()
        # Add the exported program graph and target Core AI compilation
        converter.add_exported_program(exported_program, output_names=["embeddings"])
        coreai_program = converter.to_coreai()
        
        # Save the final aimodel asset to the workspace resources folder
        import pathlib
        import shutil
        output_dir = pathlib.Path("OpenIntelligence/Resources/MLModels")
        output_dir.mkdir(parents=True, exist_ok=True)
        
        aimodel_path = output_dir / "EmbeddingModel.aimodel"
        bundle_path = output_dir / "EmbeddingModel.bundle"
        
        print(f"Saving Core AI model to: {aimodel_path}")
        if aimodel_path.exists():
            shutil.rmtree(aimodel_path)
            
        coreai_program.save_asset(aimodel_path)
        
        print(f"Renaming {aimodel_path} to {bundle_path} for Xcode deployment target compatibility...")
        if bundle_path.exists():
            shutil.rmtree(bundle_path)
        os.rename(aimodel_path, bundle_path)
        
        print("🎉 Successfully compiled and packaged EmbeddingModel.bundle!")
        
    except Exception as e:
        print(f"Model compilation failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
