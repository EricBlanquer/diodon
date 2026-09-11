namespace Diodon
{
    private static void test_sync_plugin_initialization()
    {
        Application application = new Application("org.diodon.test.sync",
            ApplicationFlags.NON_UNIQUE);
        ClipboardConfiguration configuration = new ClipboardConfiguration();
        configuration.use_clipboard = false;
        configuration.keep_clipboard_content = false;
        Controller controller = new Controller.with_configuration(configuration, false);
        Peas.Engine engine = new Peas.Engine();
        string plugin_dir = Path.build_filename(Environment.get_variable("top_builddir"),
            "plugins", "sync");
        engine.add_search_path(plugin_dir, plugin_dir);
        Peas.PluginInfo? info = engine.get_plugin_info("sync");
        if(info == null) {
            error("Could not find the clipboard sync plugin");
        }
        engine.load_plugin(info);
        if(!info.is_loaded()) {
            error("Could not load the clipboard sync plugin");
        }
        Peas.Activatable? extension = engine.create_extension(info, typeof(Peas.Activatable),
            "object", controller) as Peas.Activatable;
        if(extension == null) {
            error("Could not create the clipboard sync extension");
        }
        extension.activate();
        configuration.synchronize_between_machines = true;
        controller.on_add_item(new TextClipboardItem(ClipboardType.CLIPBOARD,
            "clipboard sync initialization", null, new DateTime.now_utc()));
        extension.deactivate();
        if(application.lookup_action("sync-import") != null) {
            error("Clipboard sync action was not removed");
        }
    }

    public static int main(string[] args)
    {
        Test.init(ref args);
        Gtk.init(ref args);
        Test.add_func("/sync/plugin_initialization", test_sync_plugin_initialization);
        return Test.run();
    }
}
