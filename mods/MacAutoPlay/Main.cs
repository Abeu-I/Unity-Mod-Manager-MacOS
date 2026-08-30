using UnityEngine;
using UnityModManagerNet;

namespace MacAutoPlay
{
    public sealed class Settings : UnityModManager.ModSettings
    {
        public bool AutoPlay;

        public override void Save(UnityModManager.ModEntry modEntry)
        {
            Save(this, modEntry);
        }
    }

    public static class Main
    {
        private static Settings settings;
        private static bool modEnabled;

        public static bool Load(UnityModManager.ModEntry modEntry)
        {
            settings = Settings.Load<Settings>(modEntry);
            modEntry.OnToggle = OnToggle;
            modEntry.OnGUI = OnGUI;
            modEntry.OnSaveGUI = OnSaveGUI;
            modEntry.OnUpdate = OnUpdate;
            modEntry.Logger.Log("Mac AutoPlay loaded. Press F8 to toggle autoplay.");
            return true;
        }

        private static bool OnToggle(UnityModManager.ModEntry modEntry, bool value)
        {
            modEnabled = value;
            if (!value)
            {
                settings.AutoPlay = false;
                Apply(false, modEntry);
            }
            return true;
        }

        private static void OnGUI(UnityModManager.ModEntry modEntry)
        {
            bool requested = GUILayout.Toggle(
                settings.AutoPlay,
                "Enable autoplay (CHEAT — custom/local play only)");
            if (requested != settings.AutoPlay)
            {
                settings.AutoPlay = requested;
                Apply(requested, modEntry);
            }
            GUILayout.Label("Hotkey: F8. Autoplay is forced off when this mod is disabled.");
        }

        private static void OnSaveGUI(UnityModManager.ModEntry modEntry)
        {
            settings.Save(modEntry);
        }

        private static void OnUpdate(UnityModManager.ModEntry modEntry, float deltaTime)
        {
            if (!modEnabled)
            {
                return;
            }
            if (Input.GetKeyDown(KeyCode.F8))
            {
                settings.AutoPlay = !settings.AutoPlay;
                Apply(settings.AutoPlay, modEntry);
            }
            if (RDC.auto != settings.AutoPlay)
            {
                RDC.auto = settings.AutoPlay;
            }
        }

        private static void Apply(bool value, UnityModManager.ModEntry modEntry)
        {
            RDC.auto = value;
            modEntry.Logger.Log("Autoplay " + (value ? "enabled" : "disabled") + ".");
        }
    }
}
