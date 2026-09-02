using System;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using UnityEngine;
using UnityModManagerNet;

namespace ModernUMMUI
{
    public static class Main
    {
        internal static UnityModManager.ModEntry Entry;
        internal static bool Enabled = true;
        private static Harmony harmony;

        public static bool Load(UnityModManager.ModEntry modEntry)
        {
            Entry = modEntry;
            modEntry.OnToggle = OnToggle;
            try
            {
                harmony = new Harmony("com.abeui.adofai.modernummui");
                MethodInfo original = AccessTools.Method(typeof(UnityModManager.UI), "WindowFunction");
                MethodInfo prefix = AccessTools.Method(typeof(MainWindowPatch), "Prefix");
                MethodInfo onGui = AccessTools.Method(typeof(UnityModManager.UI), "OnGUI");
                MethodInfo sizePrefix = AccessTools.Method(typeof(WindowSizePatch), "Prefix");
                if (original == null || prefix == null || onGui == null || sizePrefix == null)
                {
                    throw new MissingMethodException("Unity Mod Manager window method was not found.");
                }
                harmony.Patch(original, prefix: new HarmonyMethod(prefix));
                harmony.Patch(onGui, prefix: new HarmonyMethod(sizePrefix));
                modEntry.Logger.Log("Modern UMM UI enabled. Open it with Control+F10.");
                return true;
            }
            catch (Exception exception)
            {
                modEntry.Logger.LogException("Could not apply the modern UMM UI", exception);
                return false;
            }
        }

        private static bool OnToggle(UnityModManager.ModEntry modEntry, bool value)
        {
            Enabled = value;
            ModernWindow.CloseSettings();
            return true;
        }
    }

    internal static class WindowSizePatch
    {
        internal static void Prefix(object __instance)
        {
            if (Main.Enabled)
            {
                ModernWindow.EnsureWindowSize(__instance);
            }
        }
    }

    internal static class MainWindowPatch
    {
        private static bool failed;

        internal static bool Prefix(int windowId)
        {
            if (!Main.Enabled || failed)
            {
                return true;
            }
            try
            {
                ModernWindow.Draw(windowId);
                return false;
            }
            catch (Exception exception)
            {
                failed = true;
                Main.Entry.Logger.LogException("Modern UI failed; restoring the original UMM window", exception);
                return true;
            }
        }
    }

    internal static class ModernWindow
    {
        private const float SidebarWidth = 165f;
        private static readonly Color Background = Hex("11141B");
        private static readonly Color Surface = Hex("1A1F29");
        private static readonly Color SurfaceRaised = Hex("232A36");
        private static readonly Color Border = Hex("343D4D");
        private static readonly Color Text = Hex("F4F7FB");
        private static readonly Color Muted = Hex("A9B2C1");
        private static readonly Color Accent = Hex("39BDF8");
        private static readonly Color Success = Hex("52D18B");
        private static readonly Color Warning = Hex("F4B860");
        private static readonly Color Danger = Hex("FF6577");

        private static GUIStyle windowStyle;
        private static GUIStyle sidebarStyle;
        private static GUIStyle contentStyle;
        private static GUIStyle cardStyle;
        private static GUIStyle titleStyle;
        private static GUIStyle headingStyle;
        private static GUIStyle bodyStyle;
        private static GUIStyle mutedStyle;
        private static GUIStyle navStyle;
        private static GUIStyle navSelectedStyle;
        private static GUIStyle secondaryButtonStyle;
        private static GUIStyle enabledToggleStyle;
        private static GUIStyle disabledToggleStyle;
        private static GUIStyle statusStyle;
        private static GUISkin settingsSkin;
        private static Vector2 modScroll;
        private static Vector2 logScroll;
        private static Vector2 settingsScroll;
        private static int page;
        private static UnityModManager.ModEntry selectedMod;
        private static FieldInfo historyField;
        private static FieldInfo windowRectField;
        private static FieldInfo windowSizeField;
        private static FieldInfo expectedWindowSizeField;

        internal static void EnsureWindowSize(object ui)
        {
            if (ui == null || Screen.width <= 0 || Screen.height <= 0) return;

            Type uiType = typeof(UnityModManager.UI);
            if (windowRectField == null)
            {
                const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
                windowRectField = uiType.GetField("mWindowRect", flags);
                windowSizeField = uiType.GetField("mWindowSize", flags);
                expectedWindowSizeField = uiType.GetField("mExpectedWindowSize", flags);
            }
            if (windowRectField == null || windowSizeField == null || expectedWindowSizeField == null) return;

            float maximumWidth = Mathf.Max(320f, Screen.width - 40f);
            float maximumHeight = Mathf.Max(360f, Screen.height - 40f);
            float desiredWidth = Mathf.Min(1000f, Mathf.Max(760f, Screen.width * 0.82f));
            float desiredHeight = Mathf.Min(720f, Mathf.Max(560f, Screen.height * 0.78f));
            desiredWidth = Mathf.Min(desiredWidth, maximumWidth);
            desiredHeight = Mathf.Min(desiredHeight, maximumHeight);

            Rect rect = (Rect)windowRectField.GetValue(ui);
            Vector2 size = (Vector2)windowSizeField.GetValue(ui);
            if (rect.width >= desiredWidth - 2f && rect.height >= desiredHeight - 2f &&
                size.x >= desiredWidth - 2f && size.y >= desiredHeight - 2f)
            {
                return;
            }

            Rect expanded = new Rect(
                Mathf.Max(20f, (Screen.width - desiredWidth) * 0.5f),
                Mathf.Max(20f, (Screen.height - desiredHeight) * 0.5f),
                desiredWidth,
                desiredHeight);
            Vector2 expandedSize = new Vector2(desiredWidth, desiredHeight);
            windowRectField.SetValue(ui, expanded);
            windowSizeField.SetValue(ui, expandedSize);
            expectedWindowSizeField.SetValue(ui, expandedSize);
        }

        internal static void Draw(int windowId)
        {
            EnsureStyles();
            GUILayout.BeginVertical(windowStyle);
            DrawHeader();
            GUILayout.BeginHorizontal();
            DrawSidebar();
            GUILayout.BeginVertical(contentStyle, GUILayout.ExpandWidth(true), GUILayout.ExpandHeight(true));
            if (selectedMod != null)
            {
                DrawModSettings();
            }
            else if (page == 0)
            {
                DrawMods();
            }
            else if (page == 1)
            {
                DrawActivity();
            }
            else
            {
                DrawAbout();
            }
            GUILayout.EndVertical();
            GUILayout.EndHorizontal();
            GUILayout.EndVertical();
            GUI.DragWindow(new Rect(0f, 0f, 10000f, 54f));
        }

        private static void DrawHeader()
        {
            GUILayout.BeginHorizontal(GUILayout.Height(48f));
            GUILayout.Label("ADOFAI", titleStyle, GUILayout.Width(90f));
            GUILayout.Label("MOD MANAGER", headingStyle);
            GUILayout.FlexibleSpace();
            GUILayout.Label("Control + F10", mutedStyle, GUILayout.Width(112f));
            if (GUILayout.Button("Close", secondaryButtonStyle, GUILayout.Width(72f)))
            {
                CloseSettings();
                UnityModManager.UI.Instance.ToggleWindow(false);
            }
            GUILayout.EndHorizontal();
        }

        private static void DrawSidebar()
        {
            GUILayout.BeginVertical(sidebarStyle, GUILayout.Width(SidebarWidth), GUILayout.ExpandHeight(true));
            GUILayout.Space(8f);
            DrawNavButton(0, "Mods", UnityModManager.modEntries.Count + " installed");
            DrawNavButton(1, "Activity", "Manager log");
            DrawNavButton(2, "About", "Help and versions");
            GUILayout.FlexibleSpace();
            int active = 0;
            foreach (UnityModManager.ModEntry mod in UnityModManager.modEntries)
            {
                if (mod.Active) active++;
            }
            GUILayout.Label(active + " mods active", statusStyle);
            GUILayout.Label("UI only - loader unchanged", mutedStyle);
            GUILayout.EndVertical();
        }

        private static void DrawNavButton(int target, string label, string detail)
        {
            GUIStyle style = page == target && selectedMod == null ? navSelectedStyle : navStyle;
            if (GUILayout.Button(label + "\n<size=11><color=#A9B2C1>" + detail + "</color></size>", style, GUILayout.Height(58f)))
            {
                CloseSettings();
                page = target;
            }
        }

        private static void DrawMods()
        {
            int active = 0;
            int configurable = 0;
            foreach (UnityModManager.ModEntry mod in UnityModManager.modEntries)
            {
                if (mod.Active) active++;
                if (mod.OnGUI != null) configurable++;
            }
            GUILayout.Label("Installed mods", titleStyle);
            GUILayout.Label(active + " active  |  " + configurable + " configurable  |  changes that require a restart are marked by UMM", mutedStyle);
            GUILayout.Space(12f);
            modScroll = GUILayout.BeginScrollView(modScroll, GUILayout.ExpandHeight(true));
            foreach (UnityModManager.ModEntry mod in UnityModManager.modEntries)
            {
                DrawModCard(mod);
                GUILayout.Space(8f);
            }
            GUILayout.EndScrollView();
        }

        private static void DrawModCard(UnityModManager.ModEntry mod)
        {
            GUILayout.BeginVertical(cardStyle);
            GUILayout.BeginHorizontal();
            GUILayout.Label(mod.Active ? "ACTIVE" : (mod.Loaded ? "LOADED" : "INACTIVE"),
                MakeStatus(mod.Active ? Success : (mod.Loaded ? Warning : Muted)), GUILayout.Width(72f));
            GUILayout.BeginVertical();
            string name = String.IsNullOrEmpty(mod.Info.DisplayName) ? mod.Info.Id : mod.Info.DisplayName;
            GUILayout.Label(name, headingStyle);
            string version = mod.Version == null ? mod.Info.Version : mod.Version.ToString();
            string author = String.IsNullOrEmpty(mod.Info.Author) ? "Unknown author" : mod.Info.Author;
            GUILayout.Label(author + "  |  v" + version, mutedStyle);
            GUILayout.EndVertical();
            GUILayout.FlexibleSpace();

            if (mod.OnGUI != null && GUILayout.Button("Settings", secondaryButtonStyle, GUILayout.Width(88f)))
            {
                OpenSettings(mod);
            }

            if (mod.Toggleable)
            {
                bool requested = GUILayout.Toggle(mod.Active, mod.Active ? "Enabled" : "Disabled",
                    mod.Active ? enabledToggleStyle : disabledToggleStyle, GUILayout.Width(92f));
                if (requested != mod.Active)
                {
                    mod.Active = requested;
                }
            }
            else
            {
                GUILayout.Label(mod.Active ? "Always on" : "Restart needed", mutedStyle, GUILayout.Width(92f));
            }
            GUILayout.EndHorizontal();
            GUILayout.EndVertical();
        }

        private static void DrawModSettings()
        {
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Back", secondaryButtonStyle, GUILayout.Width(72f)))
            {
                CloseSettings();
                return;
            }
            GUILayout.Space(10f);
            string name = String.IsNullOrEmpty(selectedMod.Info.DisplayName) ? selectedMod.Info.Id : selectedMod.Info.DisplayName;
            GUILayout.Label(name + " settings", titleStyle);
            GUILayout.EndHorizontal();
            GUILayout.Label("These controls are supplied by the mod. Changes are saved when you go back or close the manager.", mutedStyle);
            GUILayout.Space(12f);
            settingsScroll = GUILayout.BeginScrollView(settingsScroll, cardStyle, GUILayout.ExpandHeight(true));
            GUISkin oldSkin = GUI.skin;
            try
            {
                GUI.skin = settingsSkin;
                selectedMod.OnGUI(selectedMod);
            }
            finally
            {
                GUI.skin = oldSkin;
            }
            GUILayout.EndScrollView();
        }

        private static void DrawActivity()
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label("Activity", titleStyle);
            GUILayout.FlexibleSpace();
            if (GUILayout.Button("Clear log", secondaryButtonStyle, GUILayout.Width(86f)))
            {
                UnityModManager.Logger.Clear();
            }
            GUILayout.EndHorizontal();
            GUILayout.Label("Recent loader and mod messages. Errors remain visible here for troubleshooting.", mutedStyle);
            GUILayout.Space(12f);
            logScroll = GUILayout.BeginScrollView(logScroll, cardStyle, GUILayout.ExpandHeight(true));
            List<string> history = GetHistory();
            if (history.Count == 0)
            {
                GUILayout.Label("No activity yet.", mutedStyle);
            }
            else
            {
                int start = Math.Max(0, history.Count - 120);
                for (int i = start; i < history.Count; i++)
                {
                    string line = history[i] ?? String.Empty;
                    GUIStyle lineStyle = line.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0 || line.IndexOf("exception", StringComparison.OrdinalIgnoreCase) >= 0
                        ? MakeBody(Danger) : bodyStyle;
                    GUILayout.Label(line, lineStyle);
                }
            }
            GUILayout.EndScrollView();
        }

        private static void DrawAbout()
        {
            GUILayout.Label("About", titleStyle);
            GUILayout.Label("A cleaner in-game interface for Unity Mod Manager on ADOFAI.", mutedStyle);
            GUILayout.Space(14f);
            GUILayout.BeginVertical(cardStyle);
            DrawInfoRow("Open manager", "Control + F10 (or Control + Fn + F10)");
            DrawInfoRow("Unity Mod Manager", UnityModManager.version == null ? "Unknown" : UnityModManager.version.ToString());
            DrawInfoRow("Unity", UnityModManager.unityVersion == null ? "Unknown" : UnityModManager.unityVersion.ToString());
            DrawInfoRow("Modern UI", "1.0.0");
            GUILayout.EndVertical();
            GUILayout.Space(12f);
            GUILayout.BeginVertical(cardStyle);
            GUILayout.Label("What this changes", headingStyle);
            GUILayout.Label("Only the manager window. Mod loading, Steam support, game files, hotkeys and each mod's own settings callbacks still belong to UMM.", bodyStyle);
            GUILayout.Space(8f);
            GUILayout.Label("Disable this mod to return to the original UMM interface.", mutedStyle);
            GUILayout.EndVertical();
        }

        private static void DrawInfoRow(string label, string value)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Label(label, mutedStyle, GUILayout.Width(150f));
            GUILayout.Label(value, bodyStyle);
            GUILayout.EndHorizontal();
            GUILayout.Space(6f);
        }

        private static void OpenSettings(UnityModManager.ModEntry mod)
        {
            CloseSettings();
            selectedMod = mod;
            settingsScroll = Vector2.zero;
            if (mod.OnShowGUI != null) mod.OnShowGUI(mod);
        }

        internal static void CloseSettings()
        {
            if (selectedMod == null) return;
            UnityModManager.ModEntry closing = selectedMod;
            selectedMod = null;
            try
            {
                if (closing.OnSaveGUI != null) closing.OnSaveGUI(closing);
                if (closing.OnHideGUI != null) closing.OnHideGUI(closing);
            }
            catch (Exception exception)
            {
                closing.Logger.LogException("Could not close modern settings page", exception);
            }
        }

        private static List<string> GetHistory()
        {
            if (historyField == null)
            {
                historyField = typeof(UnityModManager.Logger).GetField("history", BindingFlags.Static | BindingFlags.NonPublic);
            }
            return historyField == null ? new List<string>() : (historyField.GetValue(null) as List<string> ?? new List<string>());
        }

        private static void EnsureStyles()
        {
            if (windowStyle != null) return;
            Texture2D background = MakeTexture(Background);
            Texture2D surface = MakeTexture(Surface);
            Texture2D raised = MakeTexture(SurfaceRaised);
            Texture2D border = MakeTexture(Border);
            Texture2D accent = MakeTexture(Accent);
            Texture2D success = MakeTexture(Success);

            windowStyle = BoxStyle(background, 16, 16);
            sidebarStyle = BoxStyle(surface, 12, 12);
            sidebarStyle.margin = new RectOffset(0, 12, 0, 0);
            contentStyle = BoxStyle(background, 10, 10);
            cardStyle = BoxStyle(raised, 14, 14);
            cardStyle.border = new RectOffset(1, 1, 1, 1);

            titleStyle = MakeLabel(22, Text, FontStyle.Bold);
            headingStyle = MakeLabel(16, Text, FontStyle.Bold);
            bodyStyle = MakeLabel(13, Text, FontStyle.Normal);
            bodyStyle.wordWrap = true;
            mutedStyle = MakeLabel(12, Muted, FontStyle.Normal);
            mutedStyle.wordWrap = true;
            statusStyle = MakeLabel(12, Success, FontStyle.Bold);

            navStyle = ButtonStyle(surface, Text, 13);
            navStyle.alignment = TextAnchor.MiddleLeft;
            navStyle.richText = true;
            navStyle.padding = new RectOffset(14, 10, 8, 8);
            navSelectedStyle = ButtonStyle(raised, Text, 13);
            navSelectedStyle.alignment = TextAnchor.MiddleLeft;
            navSelectedStyle.richText = true;
            navSelectedStyle.padding = new RectOffset(14, 10, 8, 8);
            navSelectedStyle.normal.background = border;

            secondaryButtonStyle = ButtonStyle(raised, Text, 13);
            enabledToggleStyle = ToggleStyle(success, Hex("07130D"));
            disabledToggleStyle = ToggleStyle(border, Text);

            settingsSkin = UnityEngine.Object.Instantiate(GUI.skin) as GUISkin;
            settingsSkin.label = MakeLabel(13, Text, FontStyle.Normal);
            settingsSkin.label.wordWrap = true;
            settingsSkin.button = secondaryButtonStyle;
            settingsSkin.toggle = disabledToggleStyle;
            settingsSkin.box = cardStyle;
            settingsSkin.textField = FieldStyle(surface, Text);
            settingsSkin.textArea = FieldStyle(surface, Text);
            settingsSkin.horizontalSlider.normal.background = border;
            settingsSkin.horizontalSliderThumb.normal.background = accent;
        }

        private static GUIStyle MakeLabel(int size, Color color, FontStyle fontStyle)
        {
            GUIStyle style = new GUIStyle(GUI.skin.label);
            style.fontSize = size;
            style.fontStyle = fontStyle;
            style.normal.textColor = color;
            style.richText = true;
            return style;
        }

        private static GUIStyle MakeBody(Color color)
        {
            GUIStyle style = new GUIStyle(bodyStyle);
            style.normal.textColor = color;
            return style;
        }

        private static GUIStyle MakeStatus(Color color)
        {
            GUIStyle style = MakeLabel(10, color, FontStyle.Bold);
            style.alignment = TextAnchor.MiddleCenter;
            return style;
        }

        private static GUIStyle BoxStyle(Texture2D texture, int horizontal, int vertical)
        {
            GUIStyle style = new GUIStyle(GUI.skin.box);
            style.normal.background = texture;
            style.padding = new RectOffset(horizontal, horizontal, vertical, vertical);
            style.margin = new RectOffset(0, 0, 0, 0);
            return style;
        }

        private static GUIStyle ButtonStyle(Texture2D texture, Color color, int fontSize)
        {
            GUIStyle style = new GUIStyle(GUI.skin.button);
            style.normal.background = texture;
            style.hover.background = texture;
            style.active.background = texture;
            style.normal.textColor = color;
            style.hover.textColor = color;
            style.active.textColor = color;
            style.fontSize = fontSize;
            style.fontStyle = FontStyle.Bold;
            style.padding = new RectOffset(12, 12, 8, 8);
            style.border = new RectOffset(1, 1, 1, 1);
            return style;
        }

        private static GUIStyle ToggleStyle(Texture2D texture, Color color)
        {
            GUIStyle style = ButtonStyle(texture, color, 12);
            style.alignment = TextAnchor.MiddleCenter;
            style.onNormal.background = texture;
            style.onHover.background = texture;
            style.onActive.background = texture;
            style.onNormal.textColor = color;
            style.onHover.textColor = color;
            style.onActive.textColor = color;
            return style;
        }

        private static GUIStyle FieldStyle(Texture2D texture, Color color)
        {
            GUIStyle style = new GUIStyle(GUI.skin.textField);
            style.normal.background = texture;
            style.focused.background = texture;
            style.normal.textColor = color;
            style.focused.textColor = color;
            style.padding = new RectOffset(8, 8, 6, 6);
            return style;
        }

        private static Texture2D MakeTexture(Color color)
        {
            Texture2D texture = new Texture2D(1, 1, TextureFormat.RGBA32, false);
            texture.name = "Modern UMM UI " + color;
            texture.hideFlags = HideFlags.HideAndDontSave;
            texture.SetPixel(0, 0, color);
            texture.Apply();
            return texture;
        }

        private static Color Hex(string value)
        {
            Color color;
            return ColorUtility.TryParseHtmlString("#" + value, out color) ? color : Color.white;
        }
    }
}
