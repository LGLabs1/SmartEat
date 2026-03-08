# Add to PowerShell Profile
# Run this command in PowerShell:
# Add-Content $PROFILE "`nSet-Alias -Name smarteat -Value 'cd c:/Users/ASUS/Desktop/SmartEat/frontend; flutter run -d chrome'"

# Or add this function to your profile:
function Start-SmartEat {
    cd "c:/Users/ASUS/Desktop/SmartEat/frontend"
    flutter run -d chrome
}

Set-Alias -Name smarteat -Value Start-SmartEat

Write-Host "Smart Eat alias created! Use 'smarteat' command to run the app."
Write-Host "To make permanent, add this to your PowerShell profile."
