param(
    [string]$Tag = "latest",
    [switch]$Push
)

$ErrorActionPreference = "Stop"

$imageName = "infarh/xray-vpn"
$fullImage = "$imageName`:$Tag"

Write-Host "[build] Building $fullImage ..."
docker build -t $fullImage .

Write-Host "[build] Build done: $fullImage"

if ($Push) {
    Write-Host "[build] Pushing $fullImage ..."
    docker push $fullImage
    Write-Host "[build] Push done"
}
