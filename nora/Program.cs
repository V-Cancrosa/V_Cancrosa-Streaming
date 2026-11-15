// Nora – aplikacja startowa Vincent-Media: jedno okno, które sprawdza wszystko i na klik uruchamia stream.
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Nora
{
    static class Program
    {
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

        [STAThread]
        static void Main(string[] args)
        {
            // jedna Nora naraz – drugie uruchomienie (skrót, strona) tylko pokazuje okno, które już działa
            using (var single = new Mutex(true, @"Local\VincentMediaNora", out bool first))
            {
                if (!first)
                {
                    var h = FindWindow(null, "Nora");
                    if (h != IntPtr.Zero) { ShowWindow(h, 9); SetForegroundWindow(h); }
                    return;
                }
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                var exeDir = Path.GetDirectoryName(Application.ExecutablePath);
                var form = new MainForm(new Core(exeDir), args);
                Application.Run(form);
                single.ReleaseMutex();
                if (form.RestartAfterClose) Process.Start(new ProcessStartInfo(Application.ExecutablePath) { UseShellExecute = true, WorkingDirectory = exeDir });
            }
        }
    }
}
