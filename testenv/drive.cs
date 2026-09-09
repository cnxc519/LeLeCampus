// 桌面端应用驱动小工具（Windows 自带 csc 可编译）
// 用法:
//   drive launch <exe路径>            启动并前置窗口，输出 RECT
//   drive click <x> <y>              移动并左键单击
//   drive type <文本>                 清空当前输入框并输入文本
//   drive key <按键序列>              发送按键（如 {ENTER} {TAB}）
//   drive shot <输出.png>             截取应用窗口
//   drive rect                        输出窗口矩形
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Windows.Forms;

class Drive {
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rectangle r);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);

    static Process App() {
        foreach (var p in Process.GetProcessesByName("LeLeDaiPao")) return p;
        Console.WriteLine("APP_NOT_RUNNING"); Environment.Exit(1); return null;
    }
    static Rectangle Rect(IntPtr h) { Rectangle r; GetWindowRect(h, out r); return r; }
    static void Foreground() { var p = App(); SetForegroundWindow(p.MainWindowHandle); System.Threading.Thread.Sleep(700); }

    static void Main(string[] args) {
        var cmd = args.Length > 0 ? args[0] : "";
        switch (cmd) {
            case "launch": {
                var psi = new ProcessStartInfo(args[1]);
                psi.EnvironmentVariables["PATH"] = "D:/qt/6.9.3/mingw_64/bin;" + Environment.GetEnvironmentVariable("PATH");
                Process.Start(psi);
                System.Threading.Thread.Sleep(7000);
                var p = App(); Foreground();
                var r = Rect(p.MainWindowHandle);
                Console.WriteLine("RECT " + r.X + "," + r.Y + " " + r.Width + "x" + r.Height);
                break;
            }
            case "rect": {
                var p = App(); Foreground();
                var r = Rect(p.MainWindowHandle);
                Console.WriteLine("RECT " + r.X + "," + r.Y + " " + r.Width + "x" + r.Height);
                break;
            }
            case "click": {
                Foreground();
                int x = int.Parse(args[1]), y = int.Parse(args[2]);
                SetCursorPos(x, y); System.Threading.Thread.Sleep(200);
                mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero);
                System.Threading.Thread.Sleep(500);
                Console.WriteLine("CLICKED");
                break;
            }
            case "type": {
                Foreground();
                SendKeys.SendWait("^a"); System.Threading.Thread.Sleep(120);
                SendKeys.SendWait("{DEL}"); System.Threading.Thread.Sleep(120);
                SendKeys.SendWait(args[1]);
                System.Threading.Thread.Sleep(300);
                Console.WriteLine("TYPED");
                break;
            }
            case "key": {
                Foreground();
                SendKeys.SendWait(args[1]);
                System.Threading.Thread.Sleep(300);
                Console.WriteLine("KEYED");
                break;
            }
            case "shot": {
                var p = App(); Foreground();
                var r = Rect(p.MainWindowHandle);
                var b = new Bitmap(r.Width, r.Height);
                var g = Graphics.FromImage(b);
                g.CopyFromScreen(r.X, r.Y, 0, 0, r.Size);
                b.Save(args[1]);
                g.Dispose(); b.Dispose();
                Console.WriteLine("SAVED " + r.Width + "x" + r.Height);
                break;
            }
        }
    }
}
