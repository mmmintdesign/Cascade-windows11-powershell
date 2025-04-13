Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class WinAPI {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint dwFlags);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}

[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
public struct MONITORINFO {
    public int cbSize;
    public RECT rcMonitor;
    public RECT rcWork;
    public int dwFlags;
}
"@

function Cascade-WindowsPerMonitor {
    $SW_RESTORE = 9
    $MONITOR_DEFAULTTONEAREST = 2
    $padding = 20
    $offsetStepX = 180
    $offsetStepY = 50

    $windowsByMonitor = @{}

    # List of window titles that are considered system windows and should be ignored
    $ignoreTitles = @(
        "Windows Shell Experience Host",
        "Program Manager",
        "Windows Input Experience",
        "Shortcut",
        "casc.ps1 - Shortcut",
        "shell_bat_scripts",
        "Settings"
    )

    # Collect visible windows grouped by monitor
    [WinAPI]::EnumWindows({
        param ($hWnd, $lParam)

        if (-not [WinAPI]::IsWindowVisible($hWnd)) { return $true }

        $title = New-Object System.Text.StringBuilder 1024
        [WinAPI]::GetWindowText($hWnd, $title, $title.Capacity) | Out-Null
        if ($title.Length -eq 0) { return $true }

        # Ignore system windows with known titles
        if ($ignoreTitles -contains $title.ToString()) { return $true }

        $monitor = [WinAPI]::MonitorFromWindow($hWnd, $MONITOR_DEFAULTTONEAREST)
        $monitorId = $monitor.ToInt64()

        if (-not $windowsByMonitor.ContainsKey($monitorId)) {
            $windowsByMonitor[$monitorId] = @()
        }

        $windowsByMonitor[$monitorId] += $hWnd
        return $true
    }, [IntPtr]::Zero)

    # Check and debug the window count
    foreach ($monitorId in $windowsByMonitor.Keys) {
        $hWndList = $windowsByMonitor[$monitorId]
        $count = $hWndList.Count

        Write-Host "Monitor ID: $monitorId"
        Write-Host "Initial Window Count: $count"

        # Filter out windows that are truly not visible or are duplicates
        $hWndList = $hWndList | Where-Object {
            $hWnd = $_
            $title = New-Object System.Text.StringBuilder 1024
            [WinAPI]::GetWindowText($hWnd, $title, $title.Capacity) | Out-Null
            return ($title.Length -gt 0)
        }

        $count = $hWndList.Count
        Write-Host "Filtered Window Count: $count"

        if ($count -eq 0) { continue }

        $monitor = [IntPtr]::Zero
        foreach ($h in $hWndList) {
            $monitor = [WinAPI]::MonitorFromWindow($h, $MONITOR_DEFAULTTONEAREST)
            break
        }

        $mi = New-Object MONITORINFO
        $mi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($mi)
        [WinAPI]::GetMonitorInfo($monitor, [ref]$mi) | Out-Null

        $workArea = $mi.rcWork
        $availableWidth  = $workArea.Right - $workArea.Left - (2 * $padding)
        $availableHeight = $workArea.Bottom - $workArea.Top - (2 * $padding)

        $windowWidth  = $availableWidth - ($offsetStepX * ($count - 1))
        $windowHeight = $availableHeight - ($offsetStepY * ($count - 1))

         # Print windows grouped by monitor
      #  foreach ($monitorId in $windowsByMonitor.Keys) {
      #     Write-Host "Monitor ID: $monitorId"
      #     foreach ($hWnd in $windowsByMonitor[$monitorId]) {
      #        $title = New-Object System.Text.StringBuilder 1024
      #        [WinAPI]::GetWindowText($hWnd, $title, $title.Capacity) | Out-Null
      #        Write-Host "  Window Handle: $hWnd, Title: $($title.ToString())"
      #     }
      #  }
        # print id titles
         foreach ($hWnd in $hWndList) {
               $title = New-Object System.Text.StringBuilder 1024
               [WinAPI]::GetWindowText($hWnd, $title, $title.Capacity) | Out-Null
               Write-Host "  Window Handle: $hWnd, Title: $($title.ToString())"
         }

        # Adjust window positions and sizes
        for ($i = 0; $i -lt $count; $i++) {
            $hWnd = $hWndList[$i]

            $x = $workArea.Left + $padding + ($i * $offsetStepX)
            $y = $workArea.Top  + $padding + ($i * $offsetStepY)

            # Ensure windows are restored
            [WinAPI]::ShowWindow($hWnd, $SW_RESTORE) | Out-Null
            [WinAPI]::MoveWindow($hWnd, $x, $y, $windowWidth, $windowHeight, $true) | Out-Null
        }
  
    }
}

Cascade-WindowsPerMonitor
