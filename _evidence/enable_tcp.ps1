# Uruchamiane z podwyzszonymi uprawnieniami (UAC). Wlacza TCP/IP dla MSSQLSERVER,
# ustawia port 1433 (IPAll), restartuje usluge i zapisuje wynik do pliku.
$ErrorActionPreference = "Stop"
$log = "C:\Users\czare\Desktop\studia\sem6\Hurtownie\NFX_Implementation\_evidence\enable_tcp_result.txt"
"START $(Get-Date -Format s)" | Out-File $log -Encoding utf8
try {
    $tcp = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp"
    Set-ItemProperty -Path $tcp           -Name Enabled         -Value 1 -Type DWord
    Set-ItemProperty -Path "$tcp\IPAll"   -Name TcpPort         -Value "1433"
    Set-ItemProperty -Path "$tcp\IPAll"   -Name TcpDynamicPorts -Value ""
    "registry: Tcp\Enabled=$((Get-ItemProperty $tcp).Enabled), IPAll TcpPort=$((Get-ItemProperty "$tcp\IPAll").TcpPort)" | Out-File $log -Append -Encoding utf8
    "Restarting MSSQLSERVER..." | Out-File $log -Append -Encoding utf8
    Restart-Service -Name MSSQLSERVER -Force
    Start-Sleep -Seconds 4
    $svc = Get-Service MSSQLSERVER
    "service state: $($svc.Status)" | Out-File $log -Append -Encoding utf8
    "OK DONE $(Get-Date -Format s)" | Out-File $log -Append -Encoding utf8
} catch {
    "ERROR: $($_.Exception.Message)" | Out-File $log -Append -Encoding utf8
}
