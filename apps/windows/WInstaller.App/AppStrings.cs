using System.Resources;

namespace WInstaller.App;

/// <summary>
/// Reads the string table generated from shared/strings/copy.yaml
/// (scripts/gen_strings_dotnet.py). Do not hardcode user-facing copy —
/// add it to copy.yaml and regenerate (ADR-0008).
/// </summary>
internal static class AppStrings
{
    private static readonly ResourceManager Manager =
        new("WInstaller.App.Strings.AppStrings", typeof(AppStrings).Assembly);

    public static string Get(string key) => Manager.GetString(key) ?? key;

    /// <summary>Fills copy.yaml-style placeholders like {drive_name}.</summary>
    public static string Format(string key, params (string Name, string Value)[] replacements)
    {
        var text = Get(key);
        foreach (var (name, value) in replacements)
        {
            text = text.Replace("{" + name + "}", value);
        }
        return text;
    }
}
