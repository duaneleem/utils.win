# MCP Gateway Auto-Start Script
Get-Content "$PSScriptRoot\.env" | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
    }
}
docker mcp gateway run --profile $env:MCP_GATEWAY_PROFILE --transport streaming --port $env:MCP_GATEWAY_PORT

