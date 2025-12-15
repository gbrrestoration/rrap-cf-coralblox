# CoralbloxCf (ADRIA Wrapper)

A containerized worker that executes **ADRIA.jl** simulations based on environment variables. It performs a single simulation job, generates spatial/temporal metrics and visualizations, uploads results to S3, and exits.

## Workflow

1.  **Configure**: Parses run parameters (Scenario, RCP, Model Constants) from ENV.
2.  **Load**: Mounts Domain data (Moore or GBR) from local/volume paths.
3.  **Run**: Executes ADRIA scenarios.
4.  **Process**: Generates VegaLite charts, GeoJSON, and Parquet metrics.
5.  **Upload**: Pushes all artifacts to a specified S3 URI.

## Requirements

- Docker
- Input Data Packages (Moore or GBR Datapackages)
- AWS S3 Credentials (via ENV or IAM role)

## Configuration

Copy the template and fill in your details:

```bash
cp .env.template .env
```

| Variable            | Description                    | Required | Example                    |
| :------------------ | :----------------------------- | :------- | :------------------------- |
| `DATA_PACKAGE`      | Domain type (`MOORE` or `GBR`) | Yes      | `MOORE`                    |
| `DATA_PACKAGE_PATH` | Path to input data folder      | Yes      | `/data/inputs/Moore_v1`    |
| `S3_OUTPUT_PATH`    | S3 URI for results             | Yes      | `s3://my-bucket/run-id`    |
| `AWS_REGION`        | AWS Region                     | Yes      | `ap-southeast-2`           |
| `NUM_SCENARIOS`     | Number of samples              | No       | `16` (Default)             |
| `RCP_SCENARIO`      | RCP Concentration              | No       | `45` (Default)             |
| `MODEL_PARAMS`      | JSON string of custom bounds   | No       | `[{"param_name":"x",...}]` |

## Usage

### 1. Build Image

```bash
docker build -t coralbloxcf .
```

### 2. Run Container

Ensure you mount your local data directory to the container path specified in `DATA_PACKAGE_PATH`.

```bash
docker run --env-file .env \
  -v $(pwd)/data:/data/inputs \
  coralbloxcf
```

### 3. Local Development (Julia REPL)

```julia
using Pkg; Pkg.instantiate()
using CoralbloxCf

# Set ENV vars manually or via package like DotEnv.jl
ENV["DATA_PACKAGE"] = "MOORE"
ENV["DATA_PACKAGE_PATH"] = "./data/Moore_v1"
# ... set other ENVs ...

CoralbloxCf.run()
```

## Outputs

The worker uploads the following structure to `S3_OUTPUT_PATH`:

- `result_set/`: Raw ADRIA result stores (netCDF/Zarr).
- `metadata.json`: Manifest of generated artifacts and run stats.
