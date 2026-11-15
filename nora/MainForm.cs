// Okno Nory: bez ramki Windows, zaokrąglone rogi, w środku interfejs HTML (WebView2) w stylu serwisu Vincent-Media.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Nora
{
    public class MainForm : Form
    {
        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);

        readonly Core core;
        readonly WebView2 web;
        readonly JavaScriptSerializer json = new JavaScriptSerializer();
        public bool RestartAfterClose;

        public MainForm(Core core, string[] args)
        {
            this.core = core;
            Text = "Nora";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(14, 15, 19);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            float k; using (var g = CreateGraphics()) k = g.DpiX / 96f;
            ClientSize = new Size((int)(560 * k), (int)(760 * k));
            MinimumSize = new Size((int)(420 * k), (int)(520 * k));
            web = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.FromArgb(14, 15, 19) };
            Controls.Add(web);
            core.Emit += o => Send(o);
            Load += async (s, e) => await InitWeb();
        }

        // cień pod oknem bez ramki
        protected override CreateParams CreateParams { get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; return cp; } }
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try { int round = 2; DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch { }   // Windows 11: zaokrąglone rogi
        }

        async Task InitWeb()
        {
            try
            {
                var dataDir = Path.Combine(core.Data, "nora-webview");
                Directory.CreateDirectory(dataDir);
                var env = await CoreWebView2Environment.CreateAsync(null, dataDir);
                await web.EnsureCoreWebView2Async(env);
            }
            catch (Exception ex)
            {
                // brak WebView2 (rzadkie na Windows 11) – zostaje dawny kreator
                MessageBox.Show("Nora potrzebuje Microsoft Edge WebView2 (jest w Windows 11).\n\n" + ex.Message + "\n\nUruchamiam dawny kreator.", "Nora", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                try { Process.Start(new ProcessStartInfo("wscript.exe", "\"" + Path.Combine(core.App, "launcher", "launcher.vbs") + "\"") { UseShellExecute = false }); } catch { }
                Close();
                return;
            }
            var cw = web.CoreWebView2;
            cw.Settings.AreDevToolsEnabled = false;
            cw.Settings.AreDefaultContextMenusEnabled = false;
            cw.Settings.IsStatusBarEnabled = false;
            cw.Settings.IsZoomControlEnabled = false;
            cw.Settings.AreBrowserAcceleratorKeysEnabled = false;
            // pliki aplikacji jako https://nora.app/… (interfejs: nora/ui/index.html, logo z launcher/)
            cw.SetVirtualHostNameToFolderMapping("nora.app", core.App, CoreWebView2HostResourceAccessKind.Allow);
            cw.WebMessageReceived += OnMessage;
            cw.NewWindowRequested += (s, e) => { e.Handled = true; Core.Open(e.Uri); };   // linki – w zwykłej przeglądarce
            cw.NavigationStarting += (s, e) => { if (!e.Uri.StartsWith("https://nora.app/")) { e.Cancel = true; Core.Open(e.Uri); } };
            cw.Navigate("https://nora.app/nora/ui/index.html");
        }

        void Send(object o)
        {
            if (IsDisposed || !IsHandleCreated) return;
            var text = json.Serialize(o);
            try { BeginInvoke((Action)(() => { try { web.CoreWebView2?.PostWebMessageAsJson(text); } catch { } })); } catch { }
        }

        void OnMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            Dictionary<string, object> m;
            try { m = json.Deserialize<Dictionary<string, object>>(e.WebMessageAsJson); } catch { return; }
            var cmd = m.TryGetValue("cmd", out var c) ? c as string : "";
            switch (cmd)
            {
                case "ready": core.Hello(); Task.Run(() => core.RunChecks()); break;
                case "drag": ReleaseCapture(); SendMessage(Handle, 0xA1, (IntPtr)2, IntPtr.Zero); break;
                case "min": WindowState = FormWindowState.Minimized; break;
                case "close": Close(); break;
                case "restart": RestartAfterClose = true; Close(); break;
                default: var arg = m.TryGetValue("arg", out var a) ? a as string : ""; Task.Run(() => core.Act(cmd, arg)); break;
            }
        }
    }
}
