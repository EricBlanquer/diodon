plugin_statusicon = shared_library('statusicon',
    [
     'statusicon-plugin.vala',
    ],
    vala_args: common_vflags,
    c_args: common_cflags,
    link_with: [libdiodon],
    dependencies: [
        gtk_dep,
        libpeas_dep,
    ],
    include_directories: [libdiodon_inc],
    install: true,
    install_dir: join_paths(pkgpluginslibdir, 'statusicon'),
)

i18n.merge_file(
    type: 'desktop',
    input: 'statusicon.plugin.in',
    output: 'statusicon.plugin',
    po_dir: podir,
    install: true,
    install_dir: join_paths(pkgpluginslibdir, 'statusicon')
)
