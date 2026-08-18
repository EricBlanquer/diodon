plugin_sync = shared_library('sync',
    [
     'sync-plugin.vala',
    ],
    vala_args: common_vflags,
    c_args: common_cflags,
    link_with: [libdiodon],
    dependencies: [
        gio_dep,
        gtk_dep,
        libpeas_dep,
    ],
    include_directories: [libdiodon_inc],
    install: true,
    install_dir: join_paths(pkgpluginslibdir, 'sync'),
)

i18n.merge_file(
    type: 'desktop',
    input: 'sync.plugin.in',
    output: 'sync.plugin',
    po_dir: podir,
    install: true,
    install_dir: join_paths(pkgpluginslibdir, 'sync')
)
