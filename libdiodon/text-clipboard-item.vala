/*
 * Diodon - GTK+ clipboard manager.
 * Copyright (C) 2010-2011 Diodon Team <diodon-team@lists.launchpad.net>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
 * License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 *  Oliver Sauder <os@esite.ch>
 */

namespace Diodon
{
    /**
     * Represents a text clipboard item holding simple text.
     */
    public class TextClipboardItem : GLib.Object, IClipboardItem
    {
        public const string HTML_MIME_TYPE = "text/html";

        private string _text;
        private string? _html;
        private string? _origin;
        private string _label;
        private string _checksum;
        private ClipboardType _clipboard_type;
        private DateTime _date_copied;

        /**
         * Default data constructor needed for reflection.
         *
         * @param clipboard_type clipboard type item is coming from
         * @param data simple text
         * @param origin origin of clipboard item as application path
         */
        public TextClipboardItem(ClipboardType clipboard_type, string data, string? origin, DateTime date_copied, string? checksum = null, string? html = null)
        {
            _clipboard_type = clipboard_type;
            _text = data;
            _html = html;
            _origin = origin;
            _date_copied = date_copied;
            _checksum = checksum;
            if(_checksum == null) {
                _checksum = Checksum.compute_for_string(ChecksumType.SHA1, _text);
            }

            string label_text = _text;
            if (label_text.length > 200) {
                label_text = label_text.substring(0, 200);
            }
            _label = string.joinv(" ", label_text.split("\n"));
            if (_label.char_count() > 50) {
                long index_char = _label.index_of_nth_char(50);
                _label = _label.substring(0, index_char) + "...";
            }
        }

        public TextClipboardItem.with_payload(ClipboardType clipboard_type, string data, string? origin,
            DateTime date_copied, string checksum, ByteArray? payload)
        {
            this(clipboard_type, data, origin, date_copied, checksum,
                payload_to_html(payload));
        }

        /**
	     * {@inheritDoc}
	     */
        public ClipboardType get_clipboard_type()
        {
            return _clipboard_type;
        }

        /**
	     * {@inheritDoc}
	     */
	    public DateTime get_date_copied()
        {
            return _date_copied;
        }

        /**
	     * {@inheritDoc}
	     */
	    public string get_text()
        {
            return _text;
        }

        /**
	     * {@inheritDoc}
	     */
	    public string? get_origin()
        {
            return _origin;
        }

        /**
	     * {@inheritDoc}
	     */
        public string get_label()
        {
            return _label;
        }

        /**
	     * {@inheritDoc}
	     */
        public string get_mime_type()
        {
            return "text/plain";
        }

        /**
	     * {@inheritDoc}
	     */
        public ClipboardCategory get_category()
        {
            return ClipboardCategory.TEXT;
        }

        /**
	     * {@inheritDoc}
	     */
        public Gtk.Image? get_image()
        {
            return null; // no image available for text content
        }

        /**
	     * {@inheritDoc}
	     */
        public Gdk.Pixbuf? get_preview_pixbuf()
        {
            return null;
        }

        /**
	     * {@inheritDoc}
	     */
        public Icon get_icon()
        {
            return ContentType.get_icon(get_mime_type());
        }

        /**
	     * {@inheritDoc}
	     */
        public ByteArray? get_payload()
        {
            if(_html == null) {
                return null;
            }

            ByteArray payload = new ByteArray();
            payload.append(_html.data);
            return payload;
        }

        /**
	     * {@inheritDoc}
	     */
        public string get_checksum()
        {
            return _checksum;
        }

        public string? get_html()
        {
            return _html;
        }

        public void to_clipboard(Gtk.Clipboard clipboard)
        {
            if(_html == null) {
                clipboard.set_text(_text, -1);
                clipboard.store();
                return;
            }

            Gtk.TargetEntry[] targets = null;
            Gtk.TargetList target_list = new Gtk.TargetList(targets);
            target_list.add_text_targets(0);
            target_list.add(Gdk.Atom.intern(HTML_MIME_TYPE, false), 0, 0);
            targets = Gtk.target_table_new_from_list(target_list);

            clipboard.set_with_owner(targets,
                (Gtk.ClipboardGetFunc)get_clipboard_data_callback,
                (Gtk.ClipboardClearFunc)clear_clipboard_data_callback, this);
            clipboard.store();
        }

        private static void get_clipboard_data_callback(Gtk.Clipboard clipboard, Gtk.SelectionData selection_data,
            uint info, void* user_data)
        {
            TextClipboardItem item = (TextClipboardItem) user_data;
            Gdk.Atom html_target = Gdk.Atom.intern(HTML_MIME_TYPE, false);
            if(selection_data.get_target() == html_target) {
                selection_data.set(html_target, 8, string_to_uchar_array(item._html));
            } else {
                selection_data.set_text(item._text, -1);
            }
        }

        private static void clear_clipboard_data_callback(Gtk.Clipboard clipboard, void* user_data)
        {
        }

        private static uchar[] string_to_uchar_array(string str)
        {
            uchar[] data = new uchar[0];
            for(int i = 0; i < str.length; ++i) {
                data += (uchar) str[i];
            }
            return data;
        }

        private static string? payload_to_html(ByteArray? payload)
        {
            if(payload == null || payload.len == 0) {
                return null;
            }
            string html = ((string) payload.data).substring(0, payload.len);
            return html.validate() ? html : null;
        }

        /**
	     * {@inheritDoc}
	     */
	    public bool equals(IClipboardItem* item)
        {
            bool equals = false;

            if(item is TextClipboardItem) {
                equals = strcmp(_text, item->get_text()) == 0;
            }

            return equals;
        }

        /**
	     * {@inheritDoc}
	     */
	    public uint hash()
        {
            return str_hash(_text);
        }
    }
}
