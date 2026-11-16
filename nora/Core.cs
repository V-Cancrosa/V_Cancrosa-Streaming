// Rdzeń Nory: kroki sprawdzania (blokady → GameRadar → wersja → pliki → głosy) i akcje (start streamu, OBS, kokpit…).
// Aktualizacje i naprawę plików robi GameRadar (update.ps1) – Nora tylko go o to prosi i pilnuje wyniku.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace Nora
{
    public class Step { public string Id, Title, State = "wait", Detail = "", Action = ""; }

    public class Core
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool DeleteFile(string path);

        public const int Port = 7777;
        public const string Site = "https://v-cancrosa.github.io/Vincent-Media/obs-game-overlay/site/";
        const string RemoteVersionUrl = "https://raw.githubusercontent.com/V-Cancrosa/Vincent-Media/main/obs-game-overlay/version.json";
        static readonly string[] TextExt = { ".ps1", ".bat", ".vbs", ".html", ".js", ".css", ".json", ".md", ".txt", ".svg", ".tsv", ".xml" };

        public readonly string Exe, App, Det, Data, Root;
        public readonly List<Step> Steps = new List<Step>
        {
            new Step { Id = "blocks", Title = "Komputer" },
            new Step { Id = "radar", Title = "GameRadar" },
            new Step { Id = "update", Title = "Nowości" },
            new Step { Id = "files", Title = "Części programu" },
            new Step { Id = "voices", Title = "Głosy postaci" },
        };
        public event Action<object> Emit;
        readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        readonly string exeHashAtStart;
        string lastErr = "";
        int running;

        public Core(string exeDir)
        {
            Exe = Path.Combine(exeDir, "Nora.exe");
            App = Path.GetDirectoryName(exeDir.TrimEnd('\\'));          // …\Vincent-Media\obs-game-overlay
            Root = Path.GetDirectoryName(App);
            Det = Path.Combine(App, "detector");
            Data = Path.Combine(Det, "data");
            exeHashAtStart = SafeHash(Exe);
        }

        // ---------------------------------------------------------------- komunikaty do okna
        void Set(string id, string state, string detail, string action = "")
        {
            var i = Steps.FindIndex(s => s.Id == id); var s0 = Steps[i];
            s0.State = state; s0.Detail = detail ?? ""; s0.Action = action ?? "";
            Emit?.Invoke(new { type = "step", i, id, state, detail = s0.Detail, action = s0.Action });
        }
        void Toast(string t) => Emit?.Invoke(new { type = "toast", text = t });
        public void Hello() => Emit?.Invoke(new { type = "init", site = Site, version = LocalVersion(), steps = Steps.Select(s => new { s.Id, s.Title }).ToArray(), protocol = ProtocolOn() });

        // ---------------------------------------------------------------- pomocnicze
        public string LocalVersion()
        {
            try { var m = Regex.Match(File.ReadAllText(Path.Combine(App, "version.json")), "\"version\"\\s*:\\s*\"([^\"]+)\""); return m.Success ? m.Groups[1].Value : "0.0.0"; } catch { return "0.0.0"; }
        }
        static bool Newer(string a, string b) { try { return new Version(a) > new Version(b); } catch { return a != b; } }
        string LocalKey() { try { return File.ReadAllText(Path.Combine(Data, "local-key.txt")).Trim(); } catch { return ""; } }
        public static void Open(string url) { try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { } }

        Dictionary<string, object> GetJson(string url, bool key = false, int timeout = 4000, bool local = true)
        {
            try
            {
                var rq = (HttpWebRequest)WebRequest.Create(url);
                if (local) rq.Proxy = null;                       // GameRadar na tym komputerze – bez proxy
                rq.Timeout = timeout; rq.ReadWriteTimeout = timeout; rq.UserAgent = "Nora";
                if (key) rq.Headers["X-VM-Key"] = LocalKey();
                using (var rs = (HttpWebResponse)rq.GetResponse())
                using (var sr = new StreamReader(rs.GetResponseStream(), Encoding.UTF8))
                    return json.Deserialize<Dictionary<string, object>>(sr.ReadToEnd());
            }
            catch (WebException ex)
            {
                lastErr = ex.Message;
                if (ex.Response is HttpWebResponse r) try { using (var sr = new StreamReader(r.GetResponseStream(), Encoding.UTF8)) return json.Deserialize<Dictionary<string, object>>(sr.ReadToEnd()); } catch { }
                return null;
            }
            catch (Exception ex) { lastErr = ex.Message; return null; }
        }
        static string S(Dictionary<string, object> d, string k) => d != null && d.TryGetValue(k, out var v) && v != null ? Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : "";
        static bool B(Dictionary<string, object> d, string k) => d != null && d.TryGetValue(k, out var v) && v is bool b && b;

        Dictionary<string, object> Radar()
        {
            foreach (var h in new[] { "localhost", "127.0.0.1", "[::1]" }) { var j = GetJson($"http://{h}:{Port}/update/status"); if (j != null) return j; }
            return null;
        }
        Dictionary<string, object> RadarApi(string path, int timeout = 6000) => GetJson($"http://localhost:{Port}{path}", true, timeout);
        static bool RadarRunning() { try { using (Mutex.OpenExisting(@"Local\VincentMediaDetector")) return true; } catch { return false; } }

        static string Hash(string path)
        {
            var b = File.ReadAllBytes(path);
            if (TextExt.Contains(Path.GetExtension(path).ToLowerInvariant()))
                b = new UTF8Encoding(false).GetBytes(new UTF8Encoding(false).GetString(b).TrimStart('\uFEFF').Replace("\r", ""));
            using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(b)).Replace("-", "").ToLowerInvariant();
        }
        static string SafeHash(string p) { try { return Hash(p); } catch { return ""; } }

        string[] LogTail(int n)
        {
            try
            {
                var lg = Path.Combine(Data, "detector.log");
                using (var fs = new FileStream(lg, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                using (var sr = new StreamReader(fs, Encoding.UTF8))
                {
                    if (fs.Length > 200000) fs.Seek(-200000, SeekOrigin.End);
                    return sr.ReadToEnd().Split('\n').Select(l => l.TrimEnd('\r')).Where(l => Regex.IsMatch(l, @"\[\d\d:\d\d:\d\d\]")).Reverse().Take(n).Reverse().ToArray();
                }
            }
            catch { return new string[0]; }
        }
        static string Clean(string l) => Regex.Replace(l ?? "", @"^[\d-]*\s*\[[\d:]+\]\s*", "");

        // ---------------------------------------------------------------- kroki
        Dictionary<string, object> radar;
        public void RunChecks()
        {
            if (Interlocked.Exchange(ref running, 1) == 1) return;
            try
            {
                foreach (var s in Steps) Set(s.Id, "wait", "");
                Emit?.Invoke(new { type = "phase", ready = false });
                StepBlocks();
                radar = StepRadar();
                if (radar != null)
                {
                    if (!StepUpdate()) return;                  // Nora się zaktualizowała – uruchomi się ponownie
                    StepFiles();
                    Emit?.Invoke(new { type = "phase", ready = true });
                    StepVoices();
                }
                else
                {
                    Set("update", "warn", "Sprawdzę, gdy GameRadar wstanie."); Set("files", "warn", "Sprawdzę, gdy GameRadar wstanie."); Set("voices", "warn", "Sprawdzę, gdy GameRadar wstanie.");
                    Emit?.Invoke(new { type = "phase", ready = true });
                }
            }
            catch { Toast("Coś poszło nie tak przy sprawdzaniu – kliknij «Spróbuj ponownie»"); }
            finally { Interlocked.Exchange(ref running, 0); Emit?.Invoke(new { type = "done" }); }
        }

        void StepBlocks()
        {
            Set("blocks", "run", "Sprawdzam, czy nic nie przeszkadza…");
            var notes = new List<string>();
            // pliki oznaczone «z internetu» (Zone.Identifier) – Windows pyta wtedy przy każdym uruchomieniu
            int unb = 0;
            foreach (var f in Directory.EnumerateFiles(App, "*", SearchOption.AllDirectories).Where(f => !f.Contains(@"\detector\data\")))
            {
                var ext = Path.GetExtension(f).ToLowerInvariant();
                if (ext != ".ps1" && ext != ".vbs" && ext != ".exe" && ext != ".dll" && ext != ".html" && ext != ".js") continue;
                if (DeleteFile(f + ":Zone.Identifier")) unb++;
            }
            if (unb > 0) notes.Add("odblokowałam pliki pobrane z internetu");
            // znacznik «zamknięte przyciskiem w serwisie» – start z Nory to Twoja decyzja
            try { File.Delete(Path.Combine(Data, "stopped.flag")); } catch { }
            string port = "";
            if (Radar() == null && !RadarRunning())
            {
                try { using (var c = new System.Net.Sockets.TcpClient()) { if (c.ConnectAsync("127.0.0.1", Port).Wait(400) && c.Connected) port = "Inny program zajął miejsce, którego używa GameRadar. Najprościej: uruchom komputer ponownie."; } } catch { }
            }
            if (FindObs() == "") notes.Add("nie widzę OBS na tym komputerze");
            if (port != "") Set("blocks", "warn", port);
            else Set("blocks", "ok", notes.Count > 0 ? "Wszystko w porządku – " + string.Join(", ", notes) + "." : "Wszystko w porządku.");
        }

        Dictionary<string, object> StepRadar()
        {
            Set("radar", "run", "Sprawdzam, czy GameRadar czuwa…");
            var st = Radar();
            for (int k = 0; k < 25 && st == null && RadarRunning(); k++) { Set("radar", "run", "GameRadar właśnie się budzi, chwilka…"); Thread.Sleep(1000); st = Radar(); }
            if (st == null && !RadarRunning())
            {
                Set("radar", "run", "Budzę GameRadara…");
                var errFile = Path.Combine(Data, "start-error.txt");
                try { Directory.CreateDirectory(Data); File.Delete(errFile); } catch { }
                var p = StartRadar(errFile);
                var t0 = DateTime.Now;
                while ((DateTime.Now - t0).TotalSeconds < 90)
                {
                    Thread.Sleep(600);
                    st = Radar(); if (st != null) break;
                    if (p != null && p.HasExited)
                    {
                        // nasza kopia się wycofała, bo GameRadar już działa (np. właśnie przechodzi na nową wersję)
                        for (int k = 0; k < 40 && st == null && RadarRunning(); k++) { Set("radar", "run", "GameRadar przechodzi na nową wersję, chwilka…"); Thread.Sleep(1000); st = Radar(); }
                        break;
                    }
                    var last = LogTail(1).FirstOrDefault();
                    Set("radar", "run", $"Budzę GameRadara… ({(int)(DateTime.Now - t0).TotalSeconds} s)");
                }
                if (st == null)
                {
                    string why = ""; try { why = File.ReadAllText(errFile); } catch { }
                    var tail = LogTail(40); var hit = tail.LastOrDefault(l => Regex.IsMatch(l, "Nie mog|nie wczytany|zablokował|ParserError"));
                    if (why.Contains("Malicious")) Set("radar", "err", "Antywirus wziął GameRadara za zagrożenie – to pomyłka. Kliknij «Pokaż» i zezwól na niego.", "defender");
                    else if (hit != null) Set("radar", "err", "GameRadar nie chce wstać. Kliknij «Co się stało», żeby zobaczyć, dlaczego.", "log");
                    else if (why.Length > 0 && !why.StartsWith("exit |")) Set("radar", "err", "GameRadar nie chce wstać. Kliknij «Co się stało», żeby zobaczyć, dlaczego.", "log");
                    else Set("radar", "err", "GameRadar nie odpowiada. Kliknij «Co się stało» albo «Spróbuj ponownie».", "log");
                    return null;
                }
            }
            if (st == null) { Set("radar", "warn", "GameRadar działa, ale nie mogę się z nim dogadać. Spróbuj za chwilę.", "retry"); return null; }
            Set("radar", "ok", "Czuwa w tle.");
            return st;
        }

        Process StartRadar(string errFile)
        {
            var dp = Path.Combine(Det, "detector.ps1").Replace("'", "''"); var ep = errFile.Replace("'", "''");
            var cmd = "try { & '" + dp + "' -Hidden; [IO.File]::WriteAllText('" + ep + "', ('exit | GameRadar zakończył się sam, kod ' + $LASTEXITCODE)) } catch { [IO.File]::WriteAllText('" + ep + "', ($_.FullyQualifiedErrorId + ' | ' + $_.Exception.Message)) }";
            try { return Process.Start(new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"" + cmd + "\"") { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Det }); }
            catch (Exception ex) { lastErr = ex.Message; return null; }
        }

        // zwraca false, gdy Nora sama się zaktualizowała i trzeba ją uruchomić ponownie
        bool StepUpdate()
        {
            Set("update", "run", "Sprawdzam, czy są nowości…");
            var local = S(radar, "installed"); if (local == "") local = LocalVersion();
            var remote = S(GetJson(RemoteVersionUrl + "?nocache=" + DateTime.Now.Ticks, false, 8000, false), "version");
            if (remote == "") { Set("update", "warn", "Nie mam internetu – sprawdzę następnym razem."); return true; }
            if (!Newer(remote, local)) { Set("update", "ok", "Masz wszystko, co najnowsze."); return true; }
            if (B(radar, "paused")) { Set("update", "warn", "Są nowości, ale trwa stream albo nagrywanie – zainstaluję je po wszystkim."); return true; }
            Set("update", "run", "Pobieram nowości…");
            var r = RadarApi("/update/run", 240000);
            if (r == null || !B(r, "ok")) { Set("update", "warn", "Nie udało się pobrać nowości – spróbuj ponownie za chwilę.", "retry"); return true; }
            if (!WaitRadarVersion(remote)) { Set("update", "warn", "Nowości zainstalowane, GameRadar jeszcze się budzi."); }
            else Set("update", "ok", "Zainstalowałam nowości.");
            if (SafeHash(Exe) != exeHashAtStart) { Emit?.Invoke(new { type = "relaunch" }); return false; }
            return true;
        }
        bool WaitRadarVersion(string v)
        {
            for (int k = 0; k < 90; k++) { Thread.Sleep(1000); var st = Radar(); if (st != null && !Newer(v, S(st, "installed"))) { radar = st; return true; } Set("update", "run", "Instaluję nowości – GameRadar zaraz wróci…"); }
            return false;
        }

        void StepFiles()
        {
            Set("files", "run", "Sprawdzam, czy niczego nie brakuje…");
            var (total, bad) = CheckFiles();
            if (total == 0) { Set("files", "warn", "Sprawdzę przy następnych nowościach."); return; }
            if (bad.Count == 0) { Set("files", "ok", "Niczego nie brakuje."); return; }
            Set("files", "run", "Czegoś brakowało – naprawiam…");
            var r = RadarApi("/update/run?force=1", 240000);
            if (r != null && B(r, "ok")) WaitRadarVersion(LocalVersion());
            (total, bad) = CheckFiles();
            if (bad.Count == 0) Set("files", "ok", "Brakowało kilku części – już naprawiłam.");
            else Set("files", "err", "Brakuje części programu, a nie mogę ich pobrać. Sprawdź internet i kliknij «Spróbuj ponownie».", "retry");
        }
        (int, List<string>) CheckFiles()
        {
            var bad = new List<string>();
            try
            {
                var m = json.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(App, "manifest.json")));
                var files = m["files"] as Dictionary<string, object>;
                foreach (var kv in files)
                {
                    var f = Path.Combine(App, kv.Key.Replace('/', '\\'));
                    if (!File.Exists(f) || SafeHash(f) != (kv.Value as string)) bad.Add(kv.Key);
                }
                return (files.Count, bad);
            }
            catch { return (0, bad); }
        }

        void StepVoices()
        {
            Set("voices", "run", "Sprawdzam głosy postaci…");
            var pp = RadarApi("/tts/piper");
            bool Need(Dictionary<string, object> x) => !B(x, "exe") || ((x["voices"] as System.Collections.ArrayList) ?? new System.Collections.ArrayList()).Cast<Dictionary<string, object>>().Any(v => B(v, "def") && !B(v, "installed"));
            string Names(Dictionary<string, object> x) => string.Join(", ", ((x["voices"] as System.Collections.ArrayList) ?? new System.Collections.ArrayList()).Cast<Dictionary<string, object>>().Where(v => B(v, "installed")).Select(v => S(v, "name")));
            if (pp == null || !pp.ContainsKey("voices")) { Set("voices", "warn", "Lepsze głosy są niedostępne – postacie mówią głosami Windows."); return; }
            if (!Need(pp) && !B(pp, "busy")) { Set("voices", "ok", "Gotowe: " + Names(pp) + "."); return; }
            if (!B(pp, "busy")) pp = RadarApi("/tts/piper?install=1");
            var t0 = DateTime.Now;
            while (pp != null && B(pp, "busy") && (DateTime.Now - t0).TotalMinutes < 30) { Set("voices", "run", $"Pobieram głosy postaci – {S(pp, "pct")}%. Możesz już streamować."); Thread.Sleep(1000); pp = RadarApi("/tts/piper"); }
            if (pp == null) Set("voices", "warn", "Pobieranie głosów się urwało – spróbuj ponownie.", "retry");
            else if (S(pp, "error") != "") Set("voices", "warn", "Nie udało się pobrać głosów – spróbuj ponownie.", "retry");
            else Set("voices", "ok", "Pobrałam: " + Names(pp) + ".");
        }

        // ---------------------------------------------------------------- akcje z okna
        public void Act(string cmd, string arg)
        {
            try
            {
                switch (cmd)
                {
                    case "start": StartStream(); break;
                    case "obs": Toast(StartObs()); break;
                    case "cockpit": Emit?.Invoke(new { type = "show", page = "live.html" }); break;
                    case "site": Emit?.Invoke(new { type = "show", page = string.IsNullOrEmpty(arg) ? "index.html" : arg }); break;
                    case "browser": Open(Site + (string.IsNullOrEmpty(arg) ? "index.html" : arg)); break;
                    case "log": Emit?.Invoke(new { type = "show", page = "log.html" }); break;
                    case "retry": RunChecks(); break;
                    case "defender": Open("windowsdefender://threat"); break;
                    case "obsdl": Open("https://obsproject.com/download"); break;
                    case "folder": Open(Root); break;
                    case "shutdown": Shutdown(); break;
                    case "protocol": SetProtocol(arg == "on"); Emit?.Invoke(new { type = "protocol", on = ProtocolOn() }); break;
                }
            }
            catch { Toast("Coś poszło nie tak – spróbuj jeszcze raz"); }
        }

        // start streamu: OBS w tle (zminimalizowany) + kokpit w oknie Nory
        void StartStream()
        {
            // kokpit otwiera się w Norze (nie w przeglądarce) – nie ma jak zrobić klona
            var msgs = new List<string> { StartObs(), "kokpit przed Tobą" };
            Emit?.Invoke(new { type = "show", page = "live.html" });
            Toast(string.Join(" · ", msgs));
            Emit?.Invoke(new { type = "started" });
        }

        static string FindObs()
        {
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
                try
                {
                    using (var k = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view).OpenSubKey(@"SOFTWARE\OBS Studio"))
                    { var d = k?.GetValue("") as string; if (!string.IsNullOrEmpty(d)) { var e = Path.Combine(d, @"bin\64bit\obs64.exe"); if (File.Exists(e)) return e; } }
                }
                catch { }
            foreach (var d in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) })
            { var e = Path.Combine(d, @"obs-studio\bin\64bit\obs64.exe"); if (File.Exists(e)) return e; }
            return "";
        }
        static bool ObsRunning() => Process.GetProcessesByName("obs64").Length > 0 || Process.GetProcessesByName("obs32").Length > 0;
        string StartObs()
        {
            var theme = InstallObsTheme();
            if (ObsRunning()) return "OBS już działa";
            var obs = FindObs(); if (obs == "") return "Nie znalazłam OBS na tym komputerze";
            Process.Start(new ProcessStartInfo(obs) { WorkingDirectory = Path.GetDirectoryName(obs), WindowStyle = ProcessWindowStyle.Minimized, UseShellExecute = true });
            return "OBS startuje w tle";
        }

        // motyw wyglądu OBS «Vincent-Media» – jak Install-VMObsTheme w update.ps1
        string InstallObsTheme()
        {
            try
            {
                var src = Path.Combine(App, @"obs-theme\Yami_VincentMedia.ovt");
                var obsDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "obs-studio");
                if (!File.Exists(src) || !Directory.Exists(obsDir)) return "";
                var themes = Path.Combine(obsDir, "themes"); Directory.CreateDirectory(themes);
                File.Copy(src, Path.Combine(themes, "Yami_VincentMedia.ovt"), true);
                var flag = Path.Combine(Data, "obs-theme.json");
                if (File.Exists(flag) || ObsRunning()) return "";
                var ini = Path.Combine(obsDir, "user.ini"); if (!File.Exists(ini)) ini = Path.Combine(obsDir, "global.ini");
                if (!File.Exists(ini)) return "";
                var bytes = File.ReadAllBytes(ini); bool bom = bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
                var lines = new UTF8Encoding(false).GetString(bytes).TrimStart('\uFEFF').Split(new[] { "\r\n", "\n" }, StringSplitOptions.None).ToList();
                const string id = "com.obsproject.Yami.VincentMedia";
                int sec = lines.FindIndex(l => l.Trim() == "[Appearance]");
                if (sec < 0) { if (lines.Count > 0 && lines[lines.Count - 1] != "") lines.Add(""); lines.Add("[Appearance]"); lines.Add("Theme=" + id); }
                else
                {
                    bool done = false;
                    for (int k = sec + 1; k < lines.Count && !lines[k].StartsWith("["); k++) if (lines[k].StartsWith("Theme=")) { lines[k] = "Theme=" + id; done = true; break; }
                    if (!done) lines.Insert(sec + 1, "Theme=" + id);
                }
                File.WriteAllText(ini, string.Join("\r\n", lines), new UTF8Encoding(bom));
                File.WriteAllText(flag, "{\"set\":true}");
                return "motyw Vincent-Media";
            }
            catch { return ""; }
        }

        void Shutdown()
        {
            var st = Radar();
            if (st == null) { Toast("GameRadar śpi – zamknij OBS sam"); return; }
            var r = RadarApi("/shutdown");
            Toast(r != null && B(r, "ok") ? "Zamykam OBS i GameRadara – do zobaczenia!" : "GameRadar nie odpowiada");
        }

        // nora://… – uruchamianie Nory z serwisu (tylko za zgodą, tylko dla Twojego konta)
        static bool ProtocolOn() { try { using (var k = Registry.CurrentUser.OpenSubKey(@"Software\Classes\nora\shell\open\command")) return k != null; } catch { return false; } }
        void SetProtocol(bool on)
        {
            if (!on) { try { Registry.CurrentUser.DeleteSubKeyTree(@"Software\Classes\nora", false); } catch { } return; }
            using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\nora")) { k.SetValue("", "URL:Nora (Vincent-Media)"); k.SetValue("URL Protocol", ""); }
            using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\nora\DefaultIcon")) k.SetValue("", "\"" + Exe + "\",0");
            using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Classes\nora\shell\open\command")) k.SetValue("", "\"" + Exe + "\" \"%1\"");
        }
    }
}
