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
            
        def forward(self, input_ids):
            # input_ids shape: [1, 512]
            outputs = self.backbone(input_ids=input_ids)
            # Extract CLS token embedding at sequence index 0 (shape: [1, 384])
            embeddings = outputs.last_hidden_state[:, 0, :]
            return {"embeddings": embeddings}

    model = MiniLMEmbeddingWrapper()
    model.eval()

    # Define input shapes for export (batch size 1, sequence length 512)
    example_input = torch.ones((1, 512), dtype=torch.int32)

    print("Exporting PyTorch model to Core AI intermediate representation...")
    try:
        # Capture the model graph using PyTorch export API
        exported_program = torch.export.export(model, (example_input,))
        
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
