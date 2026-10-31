using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("PCL Custom Homepage Installer")]
[assembly: AssemblyDescription("PCL2 / PCL CE custom homepage installer")]
[assembly: AssemblyProduct("PCL Custom Homepage Installer")]
[assembly: AssemblyCompany("PCL Homepage")]
[assembly: AssemblyVersion("1.8.0.0")]
[assembly: AssemblyFileVersion("1.8.0.0")]
[assembly: AssemblyInformationalVersion("1.8")]

static class Program
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AllocConsole();

    [STAThread]
    private static int Main(string[] args)
    {
        bool guiMode = args.Length == 0;

        // The launcher is a Windows executable.  When it is called with
        // command line arguments, attach a console so the command line
        // installer can show its normal output.
        if (!guiMode)
        {
            try { AllocConsole(); }
            catch { }
        }

        string temp = Path.Combine(Path.GetTempPath(), "pclhome_" + Guid.NewGuid().ToString("N") + ".bat");

        try
        {
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("PCLHomePayload.bat"))
            {
                if (stream == null)
                {
                    ShowError("The installer payload is missing.");
                    return 2;
                }

                using (FileStream file = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    stream.CopyTo(file);
                }
            }

            string quotedArgs = QuoteArguments(args);
            ProcessStartInfo start = new ProcessStartInfo();
            start.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            start.Arguments = "/d /c \"\"" + temp + "\"" + (quotedArgs.Length > 0 ? " " + quotedArgs : "") + "\"";
            start.UseShellExecute = false;
            start.CreateNoWindow = guiMode;
            start.WorkingDirectory = Path.GetDirectoryName(temp);
            start.WindowStyle = guiMode ? ProcessWindowStyle.Hidden : ProcessWindowStyle.Normal;
            start.EnvironmentVariables["PCLHOME_LAUNCHER"] = Application.ExecutablePath;
            if (guiMode)
            {
                start.EnvironmentVariables["PCLHOME_NO_CONSOLE"] = "1";
            }
            else
            {
                start.EnvironmentVariables.Remove("PCLHOME_NO_CONSOLE");
            }

            using (Process process = Process.Start(start))
            {
                if (process == null)
                {
                    ShowError("Failed to start the installer.");
                    return 3;
                }

                process.WaitForExit();
                return process.ExitCode;
            }
        }
        catch (Exception ex)
        {
            ShowError("Failed to start the installer.\r\n\r\n" + ex.Message);
            return 4;
        }
        finally
        {
            try { File.Delete(temp); }
            catch { }
        }
    }

    private static string QuoteArguments(string[] args)
    {
        if (args == null || args.Length == 0)
        {
            return string.Empty;
        }

        StringBuilder builder = new StringBuilder();
        foreach (string value in args)
        {
            if (builder.Length > 0)
            {
                builder.Append(' ');
            }

            string escaped = (value ?? string.Empty).Replace("\"", "\\\"");
            if (escaped.EndsWith("\\", StringComparison.Ordinal))
            {
                escaped += "\\";
            }

            builder.Append('"');
            builder.Append(escaped);
            builder.Append('"');
        }

        return builder.ToString();
    }

    private static void ShowError(string message)
    {
        try
        {
            MessageBox.Show(message, "PCL Custom Homepage Installer", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        catch
        {
            try { Console.Error.WriteLine(message); }
            catch { }
        }
    }
}
