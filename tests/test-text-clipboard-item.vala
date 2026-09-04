namespace Diodon
{
    class TestTextClipboardItem : FsoFramework.Test.TestCase
    {
        public TestTextClipboardItem()
        {
            base("TestTextClipboardItem");
            add_test("test_html_payload_length", test_html_payload_length);
            add_test("test_rich_clipboard_targets", test_rich_clipboard_targets);
        }

        public void test_html_payload_length() throws GLib.Error
        {
            string html = "<strong>formatted</strong>";
            ByteArray payload = new ByteArray();
            payload.append((html + "discarded").data);
            payload.set_size(html.length);
            TextClipboardItem item = new TextClipboardItem.with_payload(ClipboardType.CLIPBOARD,
                "formatted", null, new DateTime.now_utc(), "checksum", payload);
            FsoFramework.Test.Assert.are_equal_string(html, item.get_html(),
                "HTML payload exceeded its declared length");
        }

        public void test_rich_clipboard_targets() throws GLib.Error
        {
            string text = "formatted";
            string html = "<strong>formatted</strong>";
            TextClipboardItem item = new TextClipboardItem(ClipboardType.CLIPBOARD, text, null,
                new DateTime.now_utc(), null, html);
            Gtk.Clipboard clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD);
            item.to_clipboard(clipboard);
            FsoFramework.Test.Assert.are_equal_string(text, clipboard.wait_for_text(),
                "Plain text clipboard target differs");
            Gtk.SelectionData? selection = clipboard.wait_for_contents(
                Gdk.Atom.intern(TextClipboardItem.HTML_MIME_TYPE, false));
            assert(selection != null);
            string actual_html = ((string) selection.get_data()).substring(0,
                selection.get_length());
            FsoFramework.Test.Assert.are_equal_string(html, actual_html,
                "HTML clipboard target differs");
        }
    }
}
