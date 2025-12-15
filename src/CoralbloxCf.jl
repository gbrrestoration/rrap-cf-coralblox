module CoralbloxCf

using ADRIA
using DataFrames, CSV, JSON3
using Dates, Random
using AWS, AWSS3

# Assuming minimal type defs if needed
include("types.jl")       
# S3StorageClient and upload_directory
include("storage_client.jl")     
# Visualization generation logic
include("handler_helpers.jl")     

# Define mode types for spatial data loading dispatch
abstract type SpatialDataMode end
struct DatapackageMode <: SpatialDataMode end
struct RMEMode <: SpatialDataMode end

# Convenience constants for mode selection
const DATAPACKAGE_MODE = DatapackageMode()
const RME_MODE = RMEMode()

export run

"""
    run()

Execute a single ADRIA simulation run using parameters from environment variables.
"""
function run()
    # ==========================================
    # 1. Configuration & Validation 
    # ==========================================
    
    # Required Inputs
    data_package_type = get(ENV, "DATA_PACKAGE", nothing) # "MOORE" or "GBR"
    data_path = get(ENV, "DATA_PACKAGE_PATH", nothing)
    output_s3_uri = get(ENV, "S3_OUTPUT_PATH", nothing)
    
    # Run Parameters
    rcp_scenario = get(ENV, "RCP_SCENARIO", "45")
    num_scenarios = parse(Int, get(ENV, "NUM_SCENARIOS", "16")) # Default to low number for safety
    
    # Optional Custom Parameters (JSON String)
    # Example: [{"param_name": "x", "lower": 0.1, "upper": 0.2, "third_param_flag": false}]
    model_params_json = get(ENV, "MODEL_PARAMS", "[]")

    # Scratch Space (Local container path)
    scratch_dir = get(ENV, "ADRIA_OUTPUT_DIR", "/tmp/adria_scratch")
    
    # Validation
    if isnothing(data_package_type) || isnothing(data_path)
        error("Missing required ENV: DATA_PACKAGE or DATA_PACKAGE_PATH")
    end
    if isnothing(output_s3_uri)
        error("Missing required ENV: S3_OUTPUT_PATH")
    end

    # AWS Config
    aws_region = get(ENV, "AWS_REGION", "ap-southeast-2")
    s3_endpoint = get(ENV, "S3_ENDPOINT", nothing) # Optional for MinIO/Localstack

    @info "Initializing ADRIA Run" type=data_package_type rcp=rcp_scenario scenarios=num_scenarios

    # ==========================================
    # 2. Setup Resources 
    # ==========================================

    # Initialize Storage Client
    storage_client = S3StorageClient(region=aws_region, s3_endpoint=s3_endpoint)

    # Prepare Workspace
    # We create a specific subfolder in scratch to avoid collisions
    unique_run_dir = create_unique_folder(base_dir=scratch_dir, prefix="run")
    work_dir = joinpath(unique_run_dir, "work")
    upload_staging_dir = joinpath(unique_run_dir, "uploads")
    
    mkpath(work_dir)
    mkpath(upload_staging_dir)

    # Tell ADRIA to write results here
    ENV["ADRIA_OUTPUT_DIR"] = work_dir

    # ==========================================
    # 3. Load Domain & Apply Params
    # ==========================================
    
    @info "Loading Domain" path=data_path
    
    # Dispatch based on Data Package type
    domain = nothing
    spatial_mode = nothing

    if data_package_type == "MOORE"
        domain = ADRIA.load_domain(data_path, rcp_scenario)
        spatial_mode = DatapackageMode()
    elseif data_package_type == "GBR"
        domain = ADRIA.load_domain(RMEDomain, data_path, rcp_scenario)
        spatial_mode = RMEMode()
    else
        error("Invalid DATA_PACKAGE: $data_package_type. Must be 'MOORE' or 'GBR'.")
    end

    # Parse and apply custom model parameters if present
    try
        raw_params = JSON3.read(model_params_json)
        if !isempty(raw_params)
            @info "Applying $(length(raw_params)) custom parameters"
            # Note: You will need to map the JSON dict to the ModelParam struct defined in types.jl
            # or adapt update_domain_with_params! to accept Dicts.
            # For simplicity here, assuming adaption:
            apply_params_from_json!(domain, raw_params) 
        end
    catch e
        @error "Failed to parse MODEL_PARAMS" exception=e
        rethrow(e)
    end

    # ==========================================
    # 4. Execution
    # ==========================================

    @info "Generating Scenarios"
    scenarios = ADRIA.sample(domain, num_scenarios)

    @info "Running Simulation"
    result_set = ADRIA.run_scenarios(domain, scenarios, rcp_scenario)

    # ==========================================
    # 5. Post-Processing & Exports (Project A Logic)
    # ==========================================

    # Move the raw ADRIA result set into the upload folder
    # This keeps the bucket structure clean: s3://.../uploads/{result_set, charts, geojson}
    move_result_set_to_determined_location(
        target_location=upload_staging_dir,
        folder_name="result_set"
    )

    # Save metadata JSON for the UI to consume
    open(joinpath(upload_staging_dir, "metadata.json"), "w") do io
        JSON3.write(io, Dict(
            "run_info" => Dict(
                "rcp" => rcp_scenario,
                "scenarios" => num_scenarios,
                "completed_at" => Dates.now()
            )
        ))
    end

    # ==========================================
    # 6. Upload & Cleanup
    # ==========================================

    @info "Uploading results to S3" target=output_s3_uri
    
    # Clean up memory before upload
    result_set = nothing
    domain = nothing
    GC.gc()

    # Upload
    upload_directory(storage_client, upload_staging_dir, output_s3_uri)

    # Cleanup Scratch
    rm(unique_run_dir, recursive=true, force=true)

    @info "Job Complete"
end

# Helper to bridge JSON inputs to ADRIA 
function apply_params_from_json!(domain, json_params)
    for p in json_params
        # Check if 3rd param exists in JSON, otherwise use 2-tuple
        val = if haskey(p, "optional_third") && !isnothing(p["optional_third"])
            (Float64(p["lower"]), Float64(p["upper"]), Float64(p["optional_third"]))
        else
            (Float64(p["lower"]), Float64(p["upper"]))
        end
        ADRIA.set_factor_bounds!(domain, Symbol(p["param_name"]), val)
    end
end

end
