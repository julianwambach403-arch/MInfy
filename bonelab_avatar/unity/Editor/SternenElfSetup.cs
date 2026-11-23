// Sternenelf – Einrichtungs-Helfer für Unity (nur im Editor, landet NICHT im Mod)
//
// Menü "Tools > Sternenelf":
//   1. Import + Materialien einrichten  (FBX im Project-Fenster auswählen)
//   2. Prefab mit EyeCenterOverride erstellen
//
// Ordnerstruktur erwartet:  <Ordner>/SternenElf.fbx  und  <Ordner>/textures/*.png
#if UNITY_EDITOR
using System;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

public static class SternenElfSetup
{
    const string Menu = "Tools/Sternenelf/";

    struct MatSpec
    {
        public string Name, Albedo, Emission;
        public Color Shade;
        public float Rim, EmissionStrength, LitSmoothness;
        public bool HairSpec;

        public MatSpec(string name, string albedo, Color shade, float rim = 0.25f,
                       string emission = null, float emissionStrength = 0f,
                       bool hairSpec = false, float litSmoothness = 0.15f)
        {
            Name = name; Albedo = albedo; Shade = shade; Rim = rim; Emission = emission;
            EmissionStrength = emissionStrength; HairSpec = hairSpec; LitSmoothness = litSmoothness;
        }
    }

    static readonly MatSpec[] Specs =
    {
        new MatSpec("Skin_Galaxy", "galaxy_skin", new Color(0.55f, 0.5f, 0.85f), 0.25f,
                    "galaxy_skin_emission", 0.6f, false, 0.35f),
        new MatSpec("Eyes", "eyes", new Color(0.85f, 0.75f, 0.65f), 0f, "eyes_emission", 2.0f),
        new MatSpec("Hair", "hair", new Color(0.45f, 0.6f, 0.85f), 0.35f, null, 0f, true, 0.2f),
        new MatSpec("Hoodie", "hoodie", new Color(0.62f, 0.78f, 0.82f)),
        new MatSpec("Hoodie_Trim", "hoodie_trim", new Color(0.7f, 0.75f, 0.7f)),
        new MatSpec("Pants", "pants", new Color(0.6f, 0.6f, 0.8f)),
        new MatSpec("Shoes", "shoes", new Color(0.7f, 0.8f, 0.85f)),
        new MatSpec("Dark", "dark", Color.white, 0f),
        new MatSpec("Zipper", "zipper", new Color(0.7f, 0.8f, 0.8f), 0.1f, null, 0f, false, 0.5f),
    };

    [MenuItem(Menu + "1. Import + Materialien einrichten")]
    static void SetupImport()
    {
        string fbxPath = AssetDatabase.GetAssetPath(Selection.activeObject);
        if (string.IsNullOrEmpty(fbxPath) || !fbxPath.EndsWith(".fbx", StringComparison.OrdinalIgnoreCase))
        {
            EditorUtility.DisplayDialog("Sternenelf", "Bitte zuerst SternenElf.fbx im Project-Fenster auswählen.", "OK");
            return;
        }

        string dir = Path.GetDirectoryName(fbxPath).Replace('\\', '/');
        string texDir = dir + "/textures";
        string matDir = dir + "/Materials";
        if (!AssetDatabase.IsValidFolder(matDir))
            AssetDatabase.CreateFolder(dir, "Materials");

        Shader toon = Shader.Find("SternenElf/Toon");
        Shader lit = Shader.Find("Universal Render Pipeline/Lit");
        Shader unlit = Shader.Find("Universal Render Pipeline/Unlit");
        bool useToon = toon != null && EditorUtility.DisplayDialog("Sternenelf – Shader wählen",
            "Toon-Shader (Anime-Look, eigener Shader)\noder\nURP/Lit (offiziell empfohlen, sicher)?\n\n" +
            "Du kannst das später jederzeit neu ausführen und umschalten.",
            "Toon-Shader", "URP/Lit");
        if (!useToon && lit == null)
        {
            EditorUtility.DisplayDialog("Sternenelf", "URP/Lit nicht gefunden – ist das Marrow SDK (URP) installiert?", "OK");
            return;
        }

        var importer = (ModelImporter)AssetImporter.GetAtPath(fbxPath);
        importer.globalScale = 1f;
        importer.useFileUnits = true;
        importer.importBlendShapes = true;
        importer.weldVertices = true;
        importer.importTangents = ModelImporterTangents.CalculateMikk;   // für den Haarglanz
        importer.animationType = ModelImporterAnimationType.Human;
        importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
        importer.skinWeights = ModelImporterSkinWeights.Standard;
        importer.optimizeBones = true;
        importer.materialImportMode = ModelImporterMaterialImportMode.ImportStandard;

        foreach (var spec in Specs)
        {
            Material m = LoadOrCreate(matDir + "/" + spec.Name + ".mat", useToon ? toon : lit);
            Texture2D albedo = LoadTex(texDir, spec.Albedo);
            Texture2D emission = spec.Emission != null ? LoadTex(texDir, spec.Emission) : null;

            if (useToon)
            {
                m.SetTexture("_BaseMap", albedo);
                m.SetColor("_ShadeColor", spec.Shade);
                m.SetFloat("_RimStrength", spec.Rim);
                SetKeyword(m, "_HAIR_SPEC", "_HairSpec", spec.HairSpec);
                SetKeyword(m, "_EMISSION", "_UseEmission", emission != null);
                if (emission != null)
                {
                    m.SetTexture("_EmissionMap", emission);
                    m.SetColor("_EmissionColor", Color.white * spec.EmissionStrength);
                    m.SetFloat("_Twinkle", spec.Name == "Skin_Galaxy" ? 0.8f : 0f);
                }
            }
            else
            {
                m.SetTexture("_BaseMap", albedo);
                m.SetColor("_BaseColor", Color.white);
                m.SetFloat("_Smoothness", spec.LitSmoothness);   // niedrig = matt, nicht plastikartig
                m.SetFloat("_Metallic", 0f);
                m.SetFloat("_SpecularHighlights", 1f);
                if (emission != null)
                {
                    m.EnableKeyword("_EMISSION");
                    m.SetTexture("_EmissionMap", emission);
                    m.SetColor("_EmissionColor", Color.white * spec.EmissionStrength);
                    m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
                }
                else
                {
                    m.DisableKeyword("_EMISSION");
                }
            }
            EditorUtility.SetDirty(m);
            importer.AddRemap(new AssetImporter.SourceAssetIdentifier(typeof(Material), spec.Name), m);
        }

        // Kontur: schwarzes Unlit-Material. Die Hülle hat umgedrehte Normalen,
        // durch das normale Backface-Culling bleibt nur der Rand sichtbar.
        Material outline = LoadOrCreate(matDir + "/Outline.mat", unlit != null ? unlit : lit);
        outline.SetColor("_BaseColor", new Color(0.02f, 0.05f, 0.08f));
        outline.SetFloat("_Cull", 2f);
        EditorUtility.SetDirty(outline);
        importer.AddRemap(new AssetImporter.SourceAssetIdentifier(typeof(Material), "Outline"), outline);

        AssetDatabase.SaveAssets();
        importer.SaveAndReimport();
        Debug.Log("[Sternenelf] Import eingerichtet (" + (useToon ? "Toon-Shader" : "URP/Lit") + ").");
    }

    [MenuItem(Menu + "2. Prefab mit EyeCenterOverride erstellen")]
    static void CreatePrefab()
    {
        string fbxPath = AssetDatabase.GetAssetPath(Selection.activeObject);
        var model = AssetDatabase.LoadAssetAtPath<GameObject>(fbxPath);
        if (model == null || !fbxPath.EndsWith(".fbx", StringComparison.OrdinalIgnoreCase))
        {
            EditorUtility.DisplayDialog("Sternenelf", "Bitte zuerst SternenElf.fbx im Project-Fenster auswählen.", "OK");
            return;
        }

        var go = (GameObject)PrefabUtility.InstantiatePrefab(model);
        go.transform.position = Vector3.zero;

        // Augenmitte aus dem "Eyes"-Teilmesh des Kopfes bestimmen
        Vector3 eyeCenter = go.transform.position + new Vector3(0f, 1.63f, 0.13f);
        var head = go.GetComponentsInChildren<SkinnedMeshRenderer>().FirstOrDefault(r => r.name == "Head");
        if (head != null)
        {
            int idx = Array.FindIndex(head.sharedMaterials, m => m != null && m.name.StartsWith("Eyes"));
            if (idx >= 0 && idx < head.sharedMesh.subMeshCount)
            {
                Bounds b = head.sharedMesh.GetSubMesh(idx).bounds;
                eyeCenter = head.transform.TransformPoint(b.center);
            }
        }
        var eye = new GameObject("EyeCenterOverride");
        eye.transform.SetParent(go.transform, false);
        eye.transform.position = eyeCenter;

        string prefabPath = Path.GetDirectoryName(fbxPath).Replace('\\', '/') + "/SternenElf.prefab";
        PrefabUtility.SaveAsPrefabAssetAndConnect(go, prefabPath, InteractionMode.UserAction);
        Selection.activeGameObject = go;
        Debug.Log("[Sternenelf] Prefab erstellt: " + prefabPath +
                  "  Jetzt das Avatar-Script hinzufügen und Body/Head/Hair Meshes eintragen.");
    }

    static Material LoadOrCreate(string path, Shader shader)
    {
        var m = AssetDatabase.LoadAssetAtPath<Material>(path);
        if (m == null)
        {
            m = new Material(shader);
            AssetDatabase.CreateAsset(m, path);
        }
        else if (m.shader != shader)
        {
            m.shader = shader;
        }
        return m;
    }

    static Texture2D LoadTex(string dir, string name)
    {
        var t = AssetDatabase.LoadAssetAtPath<Texture2D>(dir + "/" + name + ".png");
        if (t == null)
            Debug.LogWarning("[Sternenelf] Textur fehlt: " + dir + "/" + name + ".png");
        return t;
    }

    static void SetKeyword(Material m, string keyword, string prop, bool on)
    {
        m.SetFloat(prop, on ? 1f : 0f);
        if (on) m.EnableKeyword(keyword); else m.DisableKeyword(keyword);
    }
}
#endif
