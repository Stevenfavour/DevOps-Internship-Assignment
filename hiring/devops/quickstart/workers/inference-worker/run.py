import importlib.metadata
import transformers.utils.import_utils as tu

# Patch gguf into the mapping so transformers can find its version
tu.PACKAGE_DISTRIBUTION_MAPPING["gguf"] = ["gguf"]

# Now run the actual worker
import inference_worker