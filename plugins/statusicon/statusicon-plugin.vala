/*
 * Diodon - GTK+ clipboard manager.
 * Copyright (C) 2025 Eric Blanquer <eric.blanquer@gmail.com>
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
    public class StatusIconPlugin : Peas.ExtensionBase, Peas.Activatable
    {
        private Gtk.StatusIcon status_icon;
        private Gtk.Menu current_menu;
        public Object object { owned get; construct; }

        public StatusIconPlugin()
        {
            Object();
        }

        public void activate()
        {
            Controller controller = object as Controller;

            if(status_icon == null) {
                status_icon = new Gtk.StatusIcon.from_icon_name("diodon-panel");
                status_icon.set_tooltip_text("Diodon");
                current_menu = controller.get_recent_menu();
                status_icon.activate.connect(() => {
                    current_menu.popup(null, null, status_icon.position_menu, 0,
                        Gtk.get_current_event_time());
                });
                controller.on_recent_menu_changed.connect(on_menu_changed);
            }

            status_icon.set_visible(true);
        }

        public void deactivate()
        {
            Controller controller = object as Controller;

            if(status_icon != null) {
                status_icon.set_visible(false);
                controller.on_recent_menu_changed.disconnect(on_menu_changed);
            }
        }

        public void update_state()
        {
        }

        private void on_menu_changed(Gtk.Menu recent_menu)
        {
            current_menu = recent_menu;
        }
    }
}

[ModuleInit]
public void peas_register_types (GLib.TypeModule module)
{
  Peas.ObjectModule objmodule = module as Peas.ObjectModule;
  objmodule.register_extension_type (typeof (Peas.Activatable),
                                     typeof (Diodon.Plugins.StatusIconPlugin));
}
