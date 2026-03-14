# Diodon

Fork of [Diodon](https://github.com/diodon-dev/diodon), a GTK+ clipboard manager.

## Fork changes

This fork adds the following improvements over the upstream version:

- **Fix 100% CPU on startup with large clipboard history** ([PR #49](https://github.com/diodon-dev/diodon/pull/49)) — Truncates text before processing and defers image decoding (lazy loading)
- **Image preview tooltip** ([PR #53](https://github.com/diodon-dev/diodon/pull/53)) — Hover over an image item in the menu to see a scaled preview
- **Pinned clipboard items** ([PR #54](https://github.com/diodon-dev/diodon/pull/54)) — Pin items to keep them always visible at the top of the menu, preserved when clearing history. Right-click to pin/unpin, or press `p`. Manage pinned items in Preferences > Pinned tab

## Installing from source

### Dependencies

    sudo apt install meson valac libgtk-3-dev libzeitgeist-2.0-dev \
        libpeas-dev libxtst-dev libx11-dev

### Build and install

    git clone https://github.com/EricBlanquer/diodon.git && cd diodon
    meson setup builddir && cd builddir
    ninja
    sudo ninja install
    sudo ldconfig
    sudo glib-compile-schemas /usr/local/share/glib-2.0/schemas/

### Replace system Diodon

If Diodon is already installed via apt, the locally built version in `/usr/local` takes precedence. Restart Diodon after installation:

    pkill -f diodon && diodon &

## Building

Diodon uses the [Meson](https://mesonbuild.com/) build system.

    meson setup builddir && cd builddir
    ninja
    ninja test
    sudo ninja install
    # only needed after the first ninja install
    sudo ldconfig

The unity scope needs to be explicitly enabled if you want to build it

    meson configure -Denable-unity-scope=true

On distributions which do not provide packages for application-indicator
building of the indicator can be disabled by adjusting builddir creation command:

    meson builddir -Ddisable-indicator-plugin=true && cd builddir

For uninstalling type this:

    sudo ninja uninstall

## Plugins

If you would like to write your own Diodon plugin please refer to [the original blog post](http://esite.ch/2011/10/19/writing-a-plugin-for-diodon/). Feel free to add your own plugins to the list below.

|  Plugin                                                  | Description                                        |
| -------------------------------------------------------- | -------------------------------------------------- |
| [Features](https://github.com/RedHatter/diodon-plugins)  | Additional features for the diodon menu.           |
| [Numbers](https://github.com/RedHatter/diodon-plugins)   | Number clipboard menu items.                       |
| [Pop Item](https://github.com/RedHatter/diodon-plugins)  | Pastes and then removes the active clipboard item. |
| [Paste All](https://github.com/RedHatter/diodon-plugins) | Paste all recent items at once                     |
| [Edit](https://github.com/RedHatter/diodon-plugins)      | Prompts to edit the active item.                   |

## Store clipboard items in memory

Diodon uses [Zeitgeist](https://gitlab.freedesktop.org/zeitgeist/zeitgeist) to store clipboard items. Per default Zeitgeist persists all events in a database on the hard disc so it is available after a reboot. If you want to store it to memory you need to set environment variable `ZEITGEIST_DATABASE_PATH` to `:memory:` with a command like the following (might differ depending on your setup):

    echo "ZEITGEIST_DATABASE_PATH=:memory:" >> ~/.pam_environment

## Support

Upstream project: [diodon-dev/diodon](https://github.com/diodon-dev/diodon)
