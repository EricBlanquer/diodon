/*
 * Diodon - GTK+ clipboard manager.
 * Copyright (C) 2026 Eric Blanquer <eric.blanquer@gmail.com>
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
 */

namespace Diodon.Plugins
{
    public class SyncPlugin : Peas.ExtensionBase, Peas.Activatable
    {
        private const string ACTION_IMPORT = "sync-import";
        private const string DESKTOP_HOST = "iop";
        private const string LAPTOP_HOST = "eric";
        private const string SSH_USER = "eric";
        private const string DIODON_BINARY = "/usr/local/bin/diodon";
        private const string APPLICATION_ID = "net.launchpad.Diodon";
        private const string KIND_FILES = "files";
        private const string KIND_IMAGE = "image";
        private const string KIND_TEXT = "text";
        private const string PACKET_HEADER = "diodon-sync-v1";
        private const string LOCATOR_PREFIX = "host-";
        private const uint LOOKUP_TIMEOUT_SECONDS = 30;
        private const uint SSH_TIMEOUT_SECONDS = 15;
        private const string SSH_CONTROL_MASTER = "ControlMaster=auto";
        private const string SSH_CONTROL_PERSIST = "ControlPersist=10m";
        private const string REMOTE_IMPORT_SCRIPT =
            "tmp=\"$(mktemp \"${TMPDIR:-/tmp}/diodon-sync.XXXXXX\")\" || exit 1\n" +
            "cleanup() { rm -f \"$tmp\"; }\n" +
            "trap cleanup EXIT HUP INT TERM\n" +
            "cat > \"$tmp\" || exit 1\n" +
            ": \"${DBUS_SESSION_BUS_ADDRESS:=unix:path=/run/user/$(id -u)/bus}\"\n" +
            "export DBUS_SESSION_BUS_ADDRESS\n" +
            "pid=\"$(gdbus call --session --dest org.freedesktop.DBus" +
            " --object-path /org/freedesktop/DBus" +
            " --method org.freedesktop.DBus.GetConnectionUnixProcessID " + APPLICATION_ID +
            " 2>/dev/null | sed -n 's/^(uint32 \\([0-9]*\\),)$/\\1/p')\"\n" +
            "if [ -z \"$pid\" ]; then\n" +
            "  echo \"" + APPLICATION_ID + " has no owner on $DBUS_SESSION_BUS_ADDRESS\" >&2\n" +
            "  exit 1\n" +
            "fi\n" +
            "read_env() { tr '\\0' '\\n' < \"/proc/$pid/environ\" | sed -n \"s/^$1=//p\" | tail -n 1; }\n" +
            "if [ -r \"/proc/$pid/environ\" ]; then\n" +
            "  display=\"$(read_env DISPLAY)\"\n" +
            "  xauthority=\"$(read_env XAUTHORITY)\"\n" +
            "  [ -n \"$display\" ] && export DISPLAY=\"$display\"\n" +
            "  [ -n \"$xauthority\" ] && export XAUTHORITY=\"$xauthority\"\n" +
            "fi\n" +
            ": \"${DISPLAY:=:0}\"\n" +
            "export DISPLAY\n" +
            DIODON_BINARY + " " + ACTION_IMPORT + " \"$tmp\"\n";

        private Controller controller;
        private ClipboardConfiguration configuration;
        private string local_hostname;
        private string? cached_peer_target;
        private HashTable<string,string> imports_in_progress;

        public Object object { owned get; construct; }

        construct
        {
            imports_in_progress = new HashTable<string,string>(str_hash, str_equal);
        }

        public void activate()
        {
            controller = object as Controller;
            if(controller == null) {
                return;
            }

            configuration = controller.get_configuration();
            local_hostname = get_local_hostname();
            controller.on_add_item.connect(on_item_added);
            controller.add_command_line_action(ACTION_IMPORT,
                "Import clipboard item received over SSH.", import_item);

            if(configuration.synchronize_between_machines) {
                Idle.add(() => {
                    warm_connection.begin();
                    return false;
                });
            }
        }

        public void deactivate()
        {
            if(controller != null) {
                controller.on_add_item.disconnect(on_item_added);
                controller.remove_command_line_action(ACTION_IMPORT);
            }
        }

        public void update_state()
        {
        }

        private void on_item_added(IClipboardItem item)
        {
            if(!configuration.synchronize_between_machines) {
                return;
            }

            if(item.get_clipboard_type() != ClipboardType.CLIPBOARD) {
                return;
            }

            if(imports_in_progress.lookup(item.get_checksum()) != null) {
                return;
            }

            if(get_item_kind(item) == null) {
                return;
            }

            Idle.add(() => {
                push_item.begin(item);
                return false;
            });
        }

        private async void push_item(IClipboardItem item)
        {
            string? packet = serialize_item(item);
            if(packet == null) {
                return;
            }

            bool reused_target = cached_peer_target != null;
            string? failure = yield send_to_peer(packet);
            if(failure != null && reused_target) {
                cached_peer_target = null;
                failure = yield send_to_peer(packet);
            }

            if(failure != null) {
                warning("Clipboard sync failed: %s", failure);
            }
        }

        private async string? send_to_peer(string packet)
        {
            string? target = null;
            try {
                target = yield resolve_peer_target();
                string? stdout_data;
                string? stderr_data;
                bool success = yield run_process(create_ssh_argv(target,
                    REMOTE_IMPORT_SCRIPT), packet, SSH_TIMEOUT_SECONDS,
                    out stdout_data, out stderr_data);
                return success ? null :
                    "%s: %s".printf(target, summarize_error(stderr_data));
            } catch(Error e) {
                return target == null ? e.message :
                    "%s: %s".printf(target, e.message);
            }
        }

        private async void warm_connection()
        {
            try {
                string target = yield resolve_peer_target();
                string? stdout_data;
                string? stderr_data;
                bool success = yield run_process(create_ssh_argv(target,
                    "true"), null, SSH_TIMEOUT_SECONDS, out stdout_data,
                    out stderr_data);
                if(!success) {
                    warning("Clipboard sync warm-up to %s failed: %s",
                        target, summarize_error(stderr_data));
                }
            } catch(Error e) {
                warning("Clipboard sync warm-up failed: %s", e.message);
            }
        }

        private static string[] create_ssh_argv(string target,
            string remote_command)
        {
            return {
                "ssh",
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=4",
                "-o", "ServerAliveInterval=2",
                "-o", "ServerAliveCountMax=1",
                "-o", SSH_CONTROL_MASTER,
                "-o", SSH_CONTROL_PERSIST,
                "-o", "ControlPath=%s".printf(get_ssh_control_path()),
                target,
                "sh -c " + Shell.quote(remote_command)
            };
        }

        private async string resolve_peer_target() throws Error
        {
            if(cached_peer_target != null) {
                return cached_peer_target;
            }

            string? peer = get_peer_hostname(local_hostname);
            if(peer == null) {
                throw new IOError.NOT_SUPPORTED(
                    "only configured for %s and %s, not %s",
                    DESKTOP_HOST, LAPTOP_HOST, local_hostname);
            }

            string locator = get_peer_locator_path(peer);
            if(!FileUtils.test(locator, FileTest.IS_EXECUTABLE)) {
                throw new IOError.NOT_FOUND("resolver %s is not executable",
                    locator);
            }

            string? stdout_data;
            string? stderr_data;
            string[] argv = { locator };
            bool success = yield run_process(argv, null, LOOKUP_TIMEOUT_SECONDS,
                out stdout_data, out stderr_data);
            if(!success) {
                throw new IOError.FAILED("resolver %s failed: %s", locator,
                    summarize_error(stderr_data));
            }

            string? host = first_non_empty_line(stdout_data);
            if(host == null) {
                throw new IOError.FAILED("resolver %s returned no host",
                    locator);
            }

            cached_peer_target = host.index_of("@") >= 0 ?
                host : "%s@%s".printf(SSH_USER, host);
            return cached_peer_target;
        }

        private static string get_ssh_control_path()
        {
            return Path.build_filename(Environment.get_user_runtime_dir(),
                "diodon-sync-ssh-%C");
        }

        private static string? serialize_item(IClipboardItem item)
        {
            string? kind = get_item_kind(item);
            if(kind == null) {
                return null;
            }

            StringBuilder packet = new StringBuilder();
            packet.append(PACKET_HEADER);
            packet.append("\n");
            packet.append_printf("kind=%s\n", kind);
            packet.append_printf("timestamp-usec=%s\n",
                timestamp_to_string(item.get_date_copied()));
            packet.append_printf("sender=%s\n", get_local_hostname().escape());
            packet.append_printf("checksum=%s\n", item.get_checksum());

            if(kind == KIND_IMAGE) {
                try {
                    ByteArray? payload = item.get_payload();
                    if(payload == null) {
                        return null;
                    }

                    packet.append_printf("label=%s\n", item.get_label().escape());
                    packet.append_printf("payload=%s\n",
                        Base64.encode(payload.data));
                } catch(Error e) {
                    warning("Clipboard sync could not serialize image: %s",
                        e.message);
                    return null;
                }
            }
            else {
                packet.append_printf("text=%s\n", item.get_text().escape());
                TextClipboardItem? text_item = item as TextClipboardItem;
                string? html = text_item == null ? null : text_item.get_html();
                if(html != null) {
                    packet.append_printf("html=%s\n", html.escape());
                }
            }

            return packet.str;
        }

        private void import_item(string[] args)
        {
            if(!configuration.synchronize_between_machines) {
                return;
            }

            if(args.length == 0 || args[0] == null || args[0] == "") {
                warning("Clipboard sync import called without payload path");
                return;
            }

            SyncPacket? packet = read_packet(args[0]);
            if(packet == null) {
                return;
            }

            if(packet.sender == local_hostname) {
                return;
            }

            if(!should_accept(packet)) {
                debug("Clipboard sync ignored older item from %s",
                    packet.sender);
                return;
            }

            IClipboardItem? item = create_clipboard_item(packet);
            if(item == null) {
                return;
            }

            add_imported_item.begin(item);
        }

        private async void add_imported_item(IClipboardItem item)
        {
            imports_in_progress.set(item.get_checksum(), item.get_checksum());
            yield controller.add_item(item);
            imports_in_progress.remove(item.get_checksum());
            item.to_clipboard(Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD));
        }

        private bool should_accept(SyncPacket packet)
        {
            IClipboardItem? current = controller.get_current_item(
                ClipboardType.CLIPBOARD);
            if(current == null) {
                return true;
            }

            // Controller.add_item only compares with the current item content.
            // Two machines can copy different values at the same time, so the
            // sync plugin orders updates by copy timestamp and lets iop win a
            // same-timestamp tie before injecting anything into history.
            int64 current_timestamp = timestamp_to_usec(
                current.get_date_copied());
            if(packet.timestamp_usec > current_timestamp) {
                return true;
            }

            if(packet.timestamp_usec < current_timestamp) {
                return false;
            }

            return machine_priority(packet.sender) >
                machine_priority(local_hostname);
        }

        private static IClipboardItem? create_clipboard_item(SyncPacket packet)
        {
            DateTime date_copied = date_from_timestamp(packet.timestamp_usec);

            try {
                if(packet.kind == KIND_TEXT) {
                    return new TextClipboardItem(ClipboardType.CLIPBOARD,
                        packet.text, null, date_copied, packet.checksum,
                        packet.html);
                }

                if(packet.kind == KIND_FILES) {
                    return new FileClipboardItem(ClipboardType.CLIPBOARD,
                        packet.text, null, date_copied, packet.checksum);
                }

                if(packet.kind == KIND_IMAGE) {
                    ByteArray payload = new ByteArray();
                    payload.append(Base64.decode(packet.payload));
                    return new ImageClipboardItem.with_payload(
                        ClipboardType.CLIPBOARD, packet.label, payload, null,
                        date_copied, packet.checksum);
                }
            } catch(FileError e) {
                debug("Clipboard sync skipped remote file item: %s", e.message);
            } catch(Error e) {
                warning("Clipboard sync could not create remote item: %s",
                    e.message);
            }

            return null;
        }

        private static SyncPacket? read_packet(string path)
        {
            string content;
            try {
                FileUtils.get_contents(path, out content);
            } catch(FileError e) {
                warning("Clipboard sync could not read import payload %s: %s",
                    path, e.message);
                return null;
            }

            string[] lines = content.split("\n");
            if(lines.length == 0 || lines[0] != PACKET_HEADER) {
                warning("Clipboard sync import payload has an unknown format");
                return null;
            }

            HashTable<string,string> values = new HashTable<string,string>(
                str_hash, str_equal);
            for(int i = 1; i < lines.length; i++) {
                int separator = lines[i].index_of("=");
                if(separator > 0) {
                    string key = lines[i].substring(0, separator);
                    string value = lines[i].substring(separator + 1);
                    values.set(key, value);
                }
            }

            string? kind = values.lookup("kind");
            string? timestamp = values.lookup("timestamp-usec");
            string? sender = values.lookup("sender");
            string? checksum = values.lookup("checksum");
            if(kind == null || timestamp == null || sender == null ||
                checksum == null) {
                warning("Clipboard sync import payload is missing metadata");
                return null;
            }

            SyncPacket packet = new SyncPacket();
            packet.kind = kind;
            packet.timestamp_usec = int64.parse(timestamp);
            packet.sender = sender.compress();
            packet.checksum = checksum;

            if(packet.kind == KIND_IMAGE) {
                string? label = values.lookup("label");
                string? payload = values.lookup("payload");
                if(label == null || payload == null) {
                    warning("Clipboard sync image payload is incomplete");
                    return null;
                }

                packet.label = label.compress();
                packet.payload = payload;
            }
            else if(packet.kind == KIND_TEXT || packet.kind == KIND_FILES) {
                string? text = values.lookup("text");
                if(text == null) {
                    warning("Clipboard sync text payload is incomplete");
                    return null;
                }

                packet.text = text.compress();

                string? html = values.lookup("html");
                packet.html = html == null ? null : html.compress();
            }
            else {
                warning("Clipboard sync import payload has an unsupported kind: %s",
                    packet.kind);
                return null;
            }

            return packet;
        }

        private static async bool run_process(string[] argv, string? stdin_data,
            uint timeout_seconds, out string? stdout_data,
            out string? stderr_data) throws Error
        {
            stdout_data = null;
            stderr_data = null;

            Subprocess process = new Subprocess.newv(argv,
                SubprocessFlags.STDIN_PIPE |
                SubprocessFlags.STDOUT_PIPE |
                SubprocessFlags.STDERR_PIPE);
            Cancellable cancellable = new Cancellable();
            uint timeout_id = 0;
            timeout_id = Timeout.add_seconds(timeout_seconds, () => {
                cancellable.cancel();
                timeout_id = 0;
                return false;
            });

            try {
                bool completed = yield process.communicate_utf8_async(
                    stdin_data, cancellable, out stdout_data, out stderr_data);
                if(timeout_id != 0) {
                    Source.remove(timeout_id);
                }
                return completed && process.get_successful();
            } catch(Error e) {
                if(timeout_id != 0) {
                    Source.remove(timeout_id);
                }
                if(cancellable.is_cancelled()) {
                    process.force_exit();
                    throw new IOError.TIMED_OUT("%s timed out after %u seconds",
                        argv[0], timeout_seconds);
                }
                throw e;
            }
        }

        private static string? get_item_kind(IClipboardItem item)
        {
            if(item is TextClipboardItem) {
                return KIND_TEXT;
            }

            if(item is ImageClipboardItem) {
                return KIND_IMAGE;
            }

            if(item is FileClipboardItem) {
                return KIND_FILES;
            }

            return null;
        }

        private static string timestamp_to_string(DateTime date_time)
        {
            return timestamp_to_usec(date_time).to_string();
        }

        private static int64 timestamp_to_usec(DateTime date_time)
        {
            return date_time.to_unix() * 1000000 +
                date_time.get_microsecond();
        }

        private static DateTime date_from_timestamp(int64 timestamp_usec)
        {
            int64 seconds = timestamp_usec / 1000000;
            int64 microseconds = timestamp_usec % 1000000;
            return new DateTime.from_unix_utc(seconds).add(
                (TimeSpan) microseconds);
        }

        private static int machine_priority(string hostname)
        {
            if(hostname == DESKTOP_HOST) {
                return 2;
            }

            if(hostname == LAPTOP_HOST) {
                return 1;
            }

            return 0;
        }

        private static string get_local_hostname()
        {
            string hostname = Environment.get_host_name();
            return hostname.split(".", 2)[0];
        }

        private static string? get_peer_hostname(string hostname)
        {
            if(hostname == DESKTOP_HOST) {
                return LAPTOP_HOST;
            }

            if(hostname == LAPTOP_HOST) {
                return DESKTOP_HOST;
            }

            return null;
        }

        private static string get_peer_locator_path(string peer)
        {
            return Path.build_filename(Environment.get_home_dir(), "binPerso",
                LOCATOR_PREFIX + peer);
        }

        private static string? first_non_empty_line(string? text)
        {
            if(text == null) {
                return null;
            }

            foreach(string line in text.split("\n")) {
                string value = line.strip();
                if(value != "") {
                    return value;
                }
            }

            return null;
        }

        private static string summarize_error(string? stderr_data)
        {
            if(stderr_data == null || stderr_data.strip() == "") {
                return "no error output";
            }

            return stderr_data.strip();
        }

        private class SyncPacket : Object
        {
            public string kind;
            public string? html;
            public int64 timestamp_usec;
            public string sender;
            public string checksum;
            public string text;
            public string label;
            public string payload;
        }
    }
}

[ModuleInit]
public void peas_register_types (GLib.TypeModule module)
{
  Peas.ObjectModule objmodule = module as Peas.ObjectModule;
  objmodule.register_extension_type (typeof (Peas.Activatable),
                                     typeof (Diodon.Plugins.SyncPlugin));
}
