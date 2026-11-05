Function Set-Hostname {
    [string]$hostnameString = ((Get-CimInstance -Class Win32_ComputerSystem).OEMStringArray).TrimStart('"FQDN=').TrimEnd('"').Split('.')[0]
    Write-Host -ForegroundColor BLUE "Duplicating system hostname: $hostnameString for the Intel(R) EMA vAgent"
    Rename-Computer -NewName $hostnameString -Force
}

Function Set-Console {
    Copy-Item "$PSScriptRoot\puTTY" "$env:ProgramData\" -Recurse -Force
    Set-Content "$env:ProgramData\puTTY\puTTY.reg" -Value $puttyReg
    regedit /s "$env:ProgramData\puTTY\puTTY.reg"
    Start-Sleep -Milliseconds 250
    Remove-Item "$env:ProgramData\puTTY\puTTY.reg" -Force
    # Un-comment the next lines to change the shell to PowerShell
    # Set-Content "$PSScriptRoot\console-shell.reg" -Value $consoleReg
    # regedit /s "$PSScriptRoot\console-shell.reg"
    # Start-Sleep -Milliseconds 250
    # Remove-Item "$PSScriptRoot\console-shell.reg" -Force
}

Function Set-LMS {
    Write-Host -ForegroundColor BLUE "Installing ME drivers and service(s)..."
    cd "$PSScriptRoot\CSME\"
    pnputil /Add-Driver *.inf /Install /SubDirs
    cd ..
}

Function Set-PSProfile {
    $profileLocation = (Split-Path -Path $PROFILE)
    If (!(Test-Path $profileLocation)) {
        New-Item "$profileLocation" -Type Directory
    }
    Set-Content $PROFILE -Value $profilePwrShell 
}

Function Set-CopyFiles {
    Set-Content "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup\start.bat" -Value $startBat
    Try {
        Invoke-WebRequest -Uri "https://github.com/device-management-toolkit/rpc-go/releases/download/v2.52.7/rpc_windows_x64.exe" -OutFile "$env:SystemRoot\System32\rpc.exe"
    } Catch {
        Write-Host -ForegroundColor RED "Failed to download RPC: $($_.Exception.Message)"
    }
} 

Function Set-ProductKey {
    
    If (Test-Path "\\host.lan\data\key.txt") {
        $productKey = (Get-Content "\\host.lan\data\key.txt")
        $keyInstall = "share"
    } ElseIf (Test-Path "$env:SystemDrive\oem\key.txt") {
        $productKey = (Get-Content "$env:SystemDrive\oem\key.txt")
        $keyInstall = "install"
    }

    If ([string]::IsNullOrEmpty($productKey)) {
        $keyInstall = "none"
    } Else {
        Try {
            Start-Process "changepk.exe" -ArgumentList "/ProductKey $productKey"
            Write-Host -ForegroundColor BLUE "Product key updated."
        } Catch {
            Write-Host -ForegroundColor RED "Something went wrong when attempting to update the product key...`n $($_.Exception.Message)"
            $keyInstall = "$keyInstall`n$($_.Exception.Message)"
        }
    }
    # Uncomment the line below for troubleshooting
    #Set-Content "$PSScriptRoot\key-path.txt" -Value $keyInstall
}

Function Set-PageFileOff {
    Try {
        $win32System = Get-CimInstance Win32_ComputerSystem
        If ($win32System.AutomaticManagedPagefile) {
            Set-CimInstance -InputObject $win32System -Property @{AutomaticManagedPagefile = $false}
        }
        Get-CimInstance Win32_PageFileSetting | Remove-CimInstance
        Write-Host -ForegroundColor BLUE "Pagefile has been disabled..."
    } Catch {
        Write-Host -ForegroundColor RED "Something went wrong when attempting to disable the pagefile...`n $($_.Exception.Message)"
    }
}

Function Set-InstallAgent {
    $emaAgent = (Test-Path "$PSScriptRoot\EmaAgent.exe")
    $emaAgentPath = "$env:ProgramFiles\Intel\EMA Agent"
    If ($emaAgent) {
        Write-Host -ForegroundColor BLUE "`n`nInstalling Intel(R) EMA vAgent service...`n"
        If (!(Test-Path "$emaAgentPath\EmaAgent.exe")) {
            New-Item -Type Directory -Path "$emaAgentPath" -Force
        } Else {
            Remove-Item "$emaAgentPath\*" -Force -Recurse
        }
        Copy-Item "$PSScriptRoot\EmaAgent.*" "$emaAgentPath\" -Force
        Set-Location "$emaAgentPath"
        Start-Process "$emaAgentPath\EmaAgent.exe" -ArgumentList "-install" -WorkingDir "$emaAgentPath" -Wait -NoNewWindow
        Start-Sleep -Milliseconds 250
        Stop-Service EmaAgent
        Write-Host -ForegroundColor GREEN "`nvAgent installed!  Making a few more changes and then rebooting to finalize agent install."
    } Else {
        Write-Host -ForegroundColor BLUE "`n`nNo Intel(R) EMA agent or MSH file found!  Nothing else left but the reboot..."
    }
}

Function Set-Reboot {
    Write-Host -ForegroundColor CYAN "`n`nDoing a little cleanup before we reboot..."
    Start-Process Dism.exe -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait -NoNewWindow
    # Optional: change to a reboot rather than agent start if a "reboot pending" condition arises 
    # Write-Host -ForegroundColor BLUE "`n`nREBOOTING NOW!"
    # shutdown -r -t 10 -f
    Start-Service EmaAgent
}

Function Main-Execution {
    # Un-comment the line below to "force" hostname updates - "Set-Reboot" function should be adjusted as well
    # Set-Hostname
    Set-Console
    Set-LMS
    Set-PSProfile
    Set-CopyFiles
    Set-ProductKey
    # OPTIONAL: Pagefile can be disabled to reduce vHDD size (only slightly)
    # Set-PageFileOff
    Set-InstallAgent
    Set-Reboot
}

$consoleReg = @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]
"Shell"="PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoLogo"
'@

$explorerReg = @'
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]
"Shell"="explorer.exe"
'@

$startBat = @'
@echo off
start /MAX "Intel(R) vProUtil console" PowerShell.exe -ExecutionPolicy Bypass -WindowStyle Minimized
'@

$profilePwrShell = @'
########################################################################################
#                                                                                      #
# PowerShell profile to customize Intel(R) EMA vAgent for Linux full-screen console    #
#                                                                                      #
########################################################################################
#
# Fullscreen UI customizations (remove title bar and controls)
#
Function Set-puttyUI {
    # Get the handle of the current puTTY window
    # $hwnd = (Get-Process puTTY).MainWindowHandle
    $hwnd = ($puttyExecution).MainWindowHandle

    if ($hwnd -ne [IntPtr]::Zero) {
        # GWL_STYLE = -16
        $style = [WinAPI]::GetWindowLong($hwnd, -16)

        # WS_CAPTION = 0x00C00000; bitwise NOT disables it
        $newStyle = $style -band -not 0x00C00000 -band -not 0x00040000

        # Apply the new style (removes title bar)
        [WinAPI]::SetWindowLong($hwnd, -16, $newStyle) | Out-Null
        [WinAPI]::ShowWindow($hwnd, 3)

        # Force the window to redraw and update changes
        # SWP_FRAMECHANGED = 0x0020, SWP_NOMOVE = 0x0002, SWP_NOSIZE = 0x0001, SWP_NOZORDER = 0x0004
        [WinAPI]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, 0, 0, 0x0027) | Out-Null
    }
}

# Create an infinite loop to keep console (puTTY) open
#
Function Start-Console {
    For (;;) {
        Start-Process "$env:ProgramData\puTTY\puTTY.exe" -ArgumentList "-serial COM2 -sercfg 115200,8,n,1,N" -WindowStyle Maximized
        Start-Sleep 1
        $script:puttyExecution = (Get-Process putty -ErrorAction SilentlyContinue)
        If (!([string]::IsNullOrEmpty($puttyExecution))) {
            Set-puttyUI
            Do {
                $script:puttyExecution = (Get-Process putty -ErrorAction SilentlyContinue)
                Start-Sleep 2
            } Until ([string]::IsNullOrEmpty($puttyExecution))
        }
        Start-Sleep 1
    }
}

# Main execution area
#
# Change title for all PowerShell sessions
#
$host.UI.RawUI.WindowTitle = "Intel(R) EMA vAgent for Linux console"

# Make API available to all
#
$global:sourceU32 = @"
using System;
using System.Runtime.InteropServices;

public class WinAPI {
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

}
"@
# Add the API functions to the session
Add-Type -TypeDefinition $sourceU32

Start-Console
'@

$puttyReg = @'
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\SimonTatham]

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY]

[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Default%20Settings]
"HostName"=""
"PortNumber"=dword:00000fa0
"AddressFamily"=dword:00000000
"CloseOnExit"=dword:00000001
"WarnOnClose"=dword:00000001
"TCPNoDelay"=dword:00000001
"TCPKeepalives"=dword:00000000
"LogHost"=""
"PreConnectCommand"=""
"ProxyExcludeList"=""
"ProxyDNS"=dword:00000001
"ProxyLocalhost"=dword:00000000
"ProxyMethod"=dword:00000000
"ProxyHost"="proxy"
"ProxyPort"=dword:00000050
"ProxyUsername"=""
"ProxyPassword"=""
"ProxyTelnetCommand"="connect %host %port\\n"
"ProxyLogToTerm"=dword:00000001
"RemoteCommand"=""
"NoPTY"=dword:00000000
"Compression"=dword:00000000
"PreferKnownHostKeys"=dword:00000001
"RekeyTime"=dword:0000003c
"RekeyBytes"="1G"
"TryAgent"=dword:00000001
"AgentFwd"=dword:00000000
"ChangeUsername"=dword:00000000
"PublicKeyFile"=""
"DetachedCertificate"=""
"AuthPlugin"=""
"SshProt"=dword:00000003
"ConnectionSharing"=dword:00000000
"ConnectionSharingUpstream"=dword:00000001
"ConnectionSharingDownstream"=dword:00000001
"SSH2DES"=dword:00000000
"SshNoAuth"=dword:00000000
"SshNoTrivialAuth"=dword:00000000
"SshBanner"=dword:00000001
"AuthTIS"=dword:00000000
"AuthKI"=dword:00000001
"SshNoShell"=dword:00000000
"TerminalType"="vt100"
"TerminalSpeed"="38400,38400"
"UserName"=""
"UserNameFromEnvironment"=dword:00000000
"LocalUserName"=""
"RFCEnviron"=dword:00000000
"PassiveTelnet"=dword:00000001
"SerialLine"="COM2"
"SerialSpeed"=dword:0001c200
"SerialDataBits"=dword:00000008
"SerialStopHalfbits"=dword:00000002
"SerialParity"=dword:00000000
"SerialFlowControl"=dword:00000001
"SUPDUPLocation"="The Internet"
"SUPDUPCharset"=dword:00000000
"SUPDUPMoreProcessing"=dword:00000000
"SUPDUPScrolling"=dword:00000000
"BackspaceIsDelete"=dword:00000001
"RXVTHomeEnd"=dword:00000000
"LinuxFunctionKeys"=dword:00000000
"ShiftedArrowKeys"=dword:00000000
"NoApplicationCursors"=dword:00000000
"NoApplicationKeys"=dword:00000000
"NoMouseReporting"=dword:00000000
"NoRemoteResize"=dword:00000000
"NoAltScreen"=dword:00000000
"NoRemoteWinTitle"=dword:00000000
"NoRemoteClearScroll"=dword:00000000
"NoDBackspace"=dword:00000000
"NoRemoteCharset"=dword:00000000
"RemoteQTitleAction"=dword:00000001
"ApplicationCursorKeys"=dword:00000000
"ApplicationKeypad"=dword:00000000
"NetHackKeypad"=dword:00000000
"TelnetKey"=dword:00000000
"TelnetRet"=dword:00000000
"AltF4"=dword:00000001
"AltSpace"=dword:00000000
"AltOnly"=dword:00000000
"LocalEcho"=dword:00000001
"LocalEdit"=dword:00000001
"AlwaysOnTop"=dword:00000000
"FullScreenOnAltEnter"=dword:00000000
"ScrollOnKey"=dword:00000000
"ScrollOnDisp"=dword:00000000
"EraseToScrollback"=dword:00000000
"ComposeKey"=dword:00000000
"CtrlAltKeys"=dword:00000001
"WinTitle"="vConsole: ~"
"ScrollbackLines"=dword:000007d0
"DECOriginMode"=dword:00000001
"AutoWrapMode"=dword:00000001
"LFImpliesCR"=dword:00000000
"CurType"=dword:00000000
"BlinkCur"=dword:00000000
"Beep"=dword:00000001
"BeepInd"=dword:00000000
"BellOverload"=dword:00000001
"BellOverloadN"=dword:00000005
"BellWaveFile"=""
"ScrollBar"=dword:00000000
"ScrollBarFullScreen"=dword:00000000
"LockSize"=dword:00000000
"BCE"=dword:00000000
"BlinkText"=dword:00000001
"WinNameAlways"=dword:00000001
"TermWidth"=dword:00000062
"TermHeight"=dword:00000024
"Font"="Lucida Console"
"FontIsBold"=dword:00000000
"FontCharSet"=dword:00000000
"FontHeight"=dword:00000010
"FontQuality"=dword:00000000
"LogFileName"="putty.log"
"LogType"=dword:00000000
"LogFileClash"=dword:ffffffff
"LogFlush"=dword:00000001
"LogHeader"=dword:00000001
"SSHLogOmitPasswords"=dword:00000001
"SSHLogOmitData"=dword:00000000
"HideMousePtr"=dword:00000000
"SunkenEdge"=dword:00000000
"WindowBorder"=dword:00000001
"Answerback"="PuTTY"
"Printer"=""
"DisableArabicShaping"=dword:00000000
"DisableBidi"=dword:00000000
"DisableBracketedPaste"=dword:00000000
"ANSIColour"=dword:00000001
"Xterm256Colour"=dword:00000001
"TrueColour"=dword:00000001
"UseSystemColours"=dword:00000000
"TryPalette"=dword:00000000
"BoldAsColour"=dword:00000001
"MouseIsXterm"=dword:00000000
"RectSelect"=dword:00000000
"PasteControls"=dword:00000000
"RawCNP"=dword:00000000
"UTF8linedraw"=dword:00000000
"PasteRTF"=dword:00000000
"MouseOverride"=dword:00000001
"MouseAutocopy"=dword:00000001
"FontVTMode"=dword:00000004
"LineCodePage"=""
"CJKAmbigWide"=dword:00000000
"UTF8Override"=dword:00000001
"CapsLockCyr"=dword:00000000
"X11Forward"=dword:00000000
"X11Display"=""
"X11AuthType"=dword:00000001
"X11AuthFile"=""
"LocalPortAcceptAll"=dword:00000000
"RemotePortAcceptAll"=dword:00000000
"BugIgnore1"=dword:00000000
"BugPlainPW1"=dword:00000000
"BugRSA1"=dword:00000000
"BugIgnore2"=dword:00000000
"BugDeriveKey2"=dword:00000000
"BugRSAPad2"=dword:00000000
"BugPKSessID2"=dword:00000000
"BugRekey2"=dword:00000000
"BugMaxPkt2"=dword:00000000
"BugOldGex2"=dword:00000000
"BugWinadj"=dword:00000000
"BugChanReq"=dword:00000000
"BugDropStart"=dword:00000001
"BugFilterKexinit"=dword:00000001
"BugRSASHA2CertUserauth"=dword:00000000
"BugHMAC2"=dword:00000000
"StampUtmp"=dword:00000001
"LoginShell"=dword:00000001
"ScrollbarOnLeft"=dword:00000000
"ShadowBold"=dword:00000000
"BoldFont"=""
"BoldFontIsBold"=dword:00000000
"BoldFontCharSet"=dword:00000000
"BoldFontHeight"=dword:00000000
"WideFont"=""
"WideFontIsBold"=dword:00000000
"WideFontCharSet"=dword:00000000
"WideFontHeight"=dword:00000000
"WideBoldFont"=""
"WideBoldFontIsBold"=dword:00000000
"WideBoldFontCharSet"=dword:00000000
"WideBoldFontHeight"=dword:00000000
"ShadowBoldOffset"=dword:00000001
"CRImpliesLF"=dword:00000000
"WindowClass"=""
"Present"=dword:00000001
"Protocol"="telnet"
"PingInterval"=dword:00000000
"PingIntervalSecs"=dword:00000000
"TerminalModes"="CS7=A,CS8=A,DISCARD=A,DSUSP=A,ECHO=A,ECHOCTL=A,ECHOE=A,ECHOK=A,ECHOKE=A,ECHONL=A,EOF=A,EOL=A,EOL2=A,ERASE=A,FLUSH=A,ICANON=A,ICRNL=A,IEXTEN=A,IGNCR=A,IGNPAR=A,IMAXBEL=A,INLCR=A,INPCK=A,INTR=A,ISIG=A,ISTRIP=A,IUCLC=A,IUTF8=A,IXANY=A,IXOFF=A,IXON=A,KILL=A,LNEXT=A,NOFLSH=A,OCRNL=A,OLCUC=A,ONLCR=A,ONLRET=A,ONOCR=A,OPOST=A,PARENB=A,PARMRK=A,PARODD=A,PENDIN=A,QUIT=A,REPRINT=A,START=A,STATUS=A,STOP=A,SUSP=A,SWTCH=A,TOSTOP=A,WERASE=A,XCASE=A"
"Environment"=""
"GssapiFwd"=dword:00000000
"Cipher"="aes,chacha20,aesgcm,3des,WARN,des,blowfish,arcfour"
"KEX"="ntru-curve25519,mlkem-curve25519,mlkem-nist,ecdh,dh-gex-sha1,dh-group18-sha512,dh-group17-sha512,dh-group16-sha512,dh-group15-sha512,dh-group14-sha1,rsa,WARN,dh-group1-sha1"
"HostKey"="ed448,ed25519,ecdsa,rsa,dsa,WARN"
"GssapiRekey"=dword:00000002
"AuthGSSAPI"=dword:00000001
"AuthGSSAPIKEX"=dword:00000001
"GSSLibs"="gssapi32,sspi,custom"
"GSSCustom"=""
"BellOverloadT"=dword:000007d0
"BellOverloadS"=dword:00001388
"Colour0"="0,255,0"
"Colour1"="0,255,0"
"Colour2"="0,0,0"
"Colour3"="85,85,85"
"Colour4"="0,255,0"
"Colour5"="0,255,0"
"Colour6"="0,0,0"
"Colour7"="85,85,85"
"Colour8"="187,0,0"
"Colour9"="255,85,85"
"Colour10"="0,187,0"
"Colour11"="85,255,85"
"Colour12"="187,187,0"
"Colour13"="255,255,85"
"Colour14"="0,0,187"
"Colour15"="85,85,255"
"Colour16"="187,0,187"
"Colour17"="255,85,255"
"Colour18"="0,187,187"
"Colour19"="85,255,255"
"Colour20"="187,187,187"
"Colour21"="255,255,255"
"Wordness0"="0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
"Wordness32"="0,1,2,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,1,1"
"Wordness64"="1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,2"
"Wordness96"="1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,1,1,1"
"Wordness128"="1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1"
"Wordness160"="1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1"
"Wordness192"="2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2"
"Wordness224"="2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,2,2,2,2,2,2,2,2"
"MousePaste"="explicit"
"CtrlShiftIns"="explicit"
"CtrlShiftCV"="none"
"PortForwardings"=""
"SSHManualHostKeys"=""
'@

###################################################################################################
Main-Execution
