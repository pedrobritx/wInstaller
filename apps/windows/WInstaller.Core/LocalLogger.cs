using System.Text.RegularExpressions;

namespace WInstaller.Core;

/// <summary>
/// A single local log entry. No ISO contents, license keys, or unrelated disk
/// contents are ever recorded (TERMINAL_AUTOMATION.md logging rules).
/// </summary>
public sealed record LogEntry(
    string OperationId,
    string Tool,
    IReadOnlyList<string> Arguments,
    int? ExitCode,
    string UserMessage,
    string? TechnicalDetail = null)
{
    public DateTimeOffset Timestamp { get; init; } = DateTimeOffset.Now;
}

/// <summary>
/// Local-only logging (REQ-LOG-001..004). Logs are stored under Local AppData
/// and can be exported with user-profile paths redacted.
/// </summary>
public sealed class LocalLogger
{
    private readonly object _lock = new();
    private readonly string? _filePath;
    private readonly List<LogEntry> _entries = [];

    public LocalLogger(string? directory = null)
    {
        var baseDirectory = directory ?? DefaultDirectory();
        if (baseDirectory is not null)
        {
            try
            {
                Directory.CreateDirectory(baseDirectory);
                _filePath = Path.Combine(baseDirectory, "winstaller.log");
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                _filePath = null;
            }
        }
    }

    public void Record(LogEntry entry)
    {
        lock (_lock)
        {
            _entries.Add(entry);
            Persist();
        }
    }

    public IReadOnlyList<LogEntry> AllEntries
    {
        get
        {
            lock (_lock)
            {
                return _entries.ToList();
            }
        }
    }

    /// <summary>A redacted, human-readable transcript suitable for support bundles.</summary>
    public string ExportText()
    {
        lock (_lock)
        {
            return string.Join("\n", _entries.Select(Format));
        }
    }

    private void Persist()
    {
        if (_filePath is null)
        {
            return;
        }
        try
        {
            File.WriteAllText(_filePath, string.Join("\n", _entries.Select(Format)));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // Logging must never take the pipeline down.
        }
    }

    public static string Format(LogEntry entry)
    {
        var time = entry.Timestamp.ToString("yyyy-MM-dd'T'HH:mm:ssK", System.Globalization.CultureInfo.InvariantCulture);
        var args = Redact(string.Join(" ", entry.Arguments));
        var exit = entry.ExitCode is { } code ? $" exit={code}" : "";
        var line = $"[{time}] {entry.OperationId} {entry.Tool} {args}{exit} — {entry.UserMessage}";
        if (!string.IsNullOrEmpty(entry.TechnicalDetail))
        {
            line += "\n    " + Redact(entry.TechnicalDetail!).Replace("\n", "\n    ");
        }
        return line;
    }

    private static readonly Regex UsersPathPattern = new(
        @"(?i)([a-z]):[\\/]users[\\/][^\\/\s]+",
        RegexOptions.Compiled);

    /// <summary>Redacts the current user's profile directory and any <c>C:\Users\name</c> path.</summary>
    public static string Redact(string text)
    {
        var result = text;
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrEmpty(profile))
        {
            result = result.Replace(profile, "~");
        }
        return UsersPathPattern.Replace(result, @"$1:\Users\<redacted>");
    }

    private static string? DefaultDirectory()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return string.IsNullOrEmpty(appData) ? null : Path.Combine(appData, "wInstaller", "logs");
    }
}
