/* gobo-trash: GoboRefined's Trash window (0.6).
 *
 * There is no gvfs on GoboLinux 017.01, so trash:/// cannot be opened in PCManFM. Deleting
 * still moves files into ~/.local/share/Trash (GLib does that by itself, freedesktop format);
 * this window lists that folder from its .trashinfo files and offers Restore, Delete for good,
 * Empty Trash and the age after which items are deleted automatically (1, 3 or 6 months).
 * All deleting is done by gobo-trash-purge (one place, written defensively).
 *
 * Build: gcc -O2 -o gobo-trash gobo-trash.c $(pkg-config --cflags --libs gtk+-3.0)
 */
#include <gtk/gtk.h>
#include <glib/gstdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

enum { COL_ICON, COL_NAME, COL_ORIG_DIR, COL_DATE, COL_KEY, COL_SORT, N_COLS };

typedef struct {
    GtkWidget *win, *view, *status, *restore_btn, *delete_btn, *empty_btn, *age_combo;
    GtkListStore *store;
    char *trash, *files_dir, *info_dir;
    GFileMonitor *monitor;
    guint reload_id;
} App;

static const int ages[] = { 1, 3, 6 };

static void reload(App *app);

static char *trash_dir(void)
{
    return g_build_filename(g_get_user_data_dir(), "Trash", NULL);
}

/* run gobo-trash-purge with arguments; TRUE on success */
static gboolean run_purge(App *app, const char *const *args, int nargs)
{
    GPtrArray *argv = g_ptr_array_new();
    GError *err = NULL;
    int status = 0, i;
    gboolean ok;

    g_ptr_array_add(argv, (gpointer)"gobo-trash-purge");
    for (i = 0; i < nargs; i++)
        g_ptr_array_add(argv, (gpointer)args[i]);
    g_ptr_array_add(argv, NULL);
    ok = g_spawn_sync(NULL, (char **)argv->pdata, NULL, G_SPAWN_SEARCH_PATH,
                      NULL, NULL, NULL, NULL, &status, &err);
    g_ptr_array_free(argv, TRUE);
    if (ok)
        ok = g_spawn_check_exit_status(status, &err);
    if (!ok)
    {
        GtkWidget *d = gtk_message_dialog_new(GTK_WINDOW(app->win), GTK_DIALOG_MODAL,
                            GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE,
                            "Could not delete everything: %s", err ? err->message : "unknown error");
        gtk_window_set_title(GTK_WINDOW(d), "Trash");
        gtk_dialog_run(GTK_DIALOG(d));
        gtk_widget_destroy(d);
    }
    g_clear_error(&err);
    return ok;
}

static gboolean confirm(App *app, const char *question, const char *button)
{
    GtkWidget *d = gtk_message_dialog_new(GTK_WINDOW(app->win), GTK_DIALOG_MODAL,
                        GTK_MESSAGE_WARNING, GTK_BUTTONS_NONE, "%s", question);
    int r;
    gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(d), "This cannot be undone.");
    gtk_dialog_add_buttons(GTK_DIALOG(d), "_Cancel", GTK_RESPONSE_CANCEL, button, GTK_RESPONSE_OK, NULL);
    gtk_dialog_set_default_response(GTK_DIALOG(d), GTK_RESPONSE_CANCEL);
    gtk_window_set_title(GTK_WINDOW(d), "Trash");
    r = gtk_dialog_run(GTK_DIALOG(d));
    gtk_widget_destroy(d);
    return r == GTK_RESPONSE_OK;
}

static void add_item(App *app, const char *key, GKeyFile *kf)
{
    char *path_esc = g_key_file_get_string(kf, "Trash Info", "Path", NULL);
    char *date = g_key_file_get_string(kf, "Trash Info", "DeletionDate", NULL);
    char *path = path_esc ? g_uri_unescape_string(path_esc, NULL) : NULL;
    char *name, *dir, *file, *date_disp;
    GIcon *icon = NULL;
    GFile *gf;
    GFileInfo *inf;
    GtkTreeIter it;

    if (!path)
        path = g_strdup(key);
    name = g_path_get_basename(path);
    dir = g_path_is_absolute(path) ? g_path_get_dirname(path) : g_strdup("(unknown)");
    file = g_build_filename(app->files_dir, key, NULL);
    gf = g_file_new_for_path(file);
    inf = g_file_query_info(gf, G_FILE_ATTRIBUTE_STANDARD_ICON, G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, NULL, NULL);
    if (inf)
    {
        icon = g_object_ref(g_file_info_get_icon(inf));
        g_object_unref(inf);
    }
    if (!icon)
        icon = g_themed_icon_new("text-x-generic");
    date_disp = date ? g_strdup(date) : g_strdup("");
    if (date_disp[0] && strlen(date_disp) >= 16)
    {   /* 2026-05-14T12:00:00 -> 2026-05-14 12:00 */
        date_disp[10] = ' ';
        date_disp[16] = '\0';
    }
    gtk_list_store_append(app->store, &it);
    gtk_list_store_set(app->store, &it, COL_ICON, icon, COL_NAME, name, COL_ORIG_DIR, dir,
                       COL_DATE, date_disp, COL_KEY, key, COL_SORT, date ? date : "", -1);
    g_object_unref(icon);
    g_object_unref(gf);
    g_free(file);
    g_free(date_disp);
    g_free(dir);
    g_free(name);
    g_free(path);
    g_free(path_esc);
    g_free(date);
}

static void update_buttons(App *app)
{
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(app->view));
    int nsel = gtk_tree_selection_count_selected_rows(sel);
    int n = gtk_tree_model_iter_n_children(GTK_TREE_MODEL(app->store), NULL);
    char *msg;

    gtk_widget_set_sensitive(app->restore_btn, nsel > 0);
    gtk_widget_set_sensitive(app->delete_btn, nsel > 0);
    gtk_widget_set_sensitive(app->empty_btn, n > 0);
    if (n == 0)
        msg = g_strdup("The Trash is empty.");
    else
        msg = g_strdup_printf(n == 1 ? "%d item" : "%d items", n);
    gtk_label_set_text(GTK_LABEL(app->status), msg);
    g_free(msg);
}

static void reload(App *app)
{
    GDir *d;
    const char *ent;

    gtk_list_store_clear(app->store);
    d = g_dir_open(app->info_dir, 0, NULL);
    if (d)
    {
        while ((ent = g_dir_read_name(d)) != NULL)
        {
            char *key, *info, *file;
            GKeyFile *kf;
            if (!g_str_has_suffix(ent, ".trashinfo"))
                continue;
            key = g_strndup(ent, strlen(ent) - strlen(".trashinfo"));
            info = g_build_filename(app->info_dir, ent, NULL);
            file = g_build_filename(app->files_dir, key, NULL);
            kf = g_key_file_new();
            /* list only items whose file is still there */
            if (g_file_test(file, G_FILE_TEST_EXISTS) || g_file_test(file, G_FILE_TEST_IS_SYMLINK))
            {
                if (!g_key_file_load_from_file(kf, info, G_KEY_FILE_NONE, NULL))
                {
                    g_key_file_free(kf);
                    kf = g_key_file_new();
                }
                add_item(app, key, kf);
            }
            g_key_file_free(kf);
            g_free(file);
            g_free(info);
            g_free(key);
        }
        g_dir_close(d);
    }
    update_buttons(app);
}

static gboolean reload_idle(gpointer data)
{
    App *app = data;
    app->reload_id = 0;
    reload(app);
    return FALSE;
}

static void on_trash_changed(GFileMonitor *m, GFile *f, GFile *o, GFileMonitorEvent e, App *app)
{
    if (!app->reload_id)
        app->reload_id = g_timeout_add(300, reload_idle, app);
}

/* collect the keys (names inside Trash/files) of the selected rows */
static GPtrArray *selected_keys(App *app)
{
    GtkTreeSelection *sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(app->view));
    GList *rows = gtk_tree_selection_get_selected_rows(sel, NULL), *l;
    GPtrArray *keys = g_ptr_array_new_with_free_func(g_free);
    for (l = rows; l; l = l->next)
    {
        GtkTreeIter it;
        char *key;
        if (gtk_tree_model_get_iter(GTK_TREE_MODEL(app->store), &it, l->data))
        {
            gtk_tree_model_get(GTK_TREE_MODEL(app->store), &it, COL_KEY, &key, -1);
            g_ptr_array_add(keys, key);
        }
    }
    g_list_free_full(rows, (GDestroyNotify)gtk_tree_path_free);
    return keys;
}

/* a free name next to the original: "name", "name (restored)", "name (restored 2)"... */
static char *free_target(const char *orig)
{
    char *dir = g_path_get_dirname(orig), *base = g_path_get_basename(orig);
    char *dot = strrchr(base, '.'), *stem, *ext, *t;
    int n;
    if (!g_file_test(orig, G_FILE_TEST_EXISTS) && !g_file_test(orig, G_FILE_TEST_IS_SYMLINK))
    {
        g_free(dir); g_free(base);
        return g_strdup(orig);
    }
    if (dot && dot != base)
    {
        stem = g_strndup(base, dot - base);
        ext = g_strdup(dot);
    }
    else
    {
        stem = g_strdup(base);
        ext = g_strdup("");
    }
    for (n = 1; ; n++)
    {
        char *name = n == 1 ? g_strdup_printf("%s (restored)%s", stem, ext)
                            : g_strdup_printf("%s (restored %d)%s", stem, n, ext);
        t = g_build_filename(dir, name, NULL);
        g_free(name);
        if (!g_file_test(t, G_FILE_TEST_EXISTS) && !g_file_test(t, G_FILE_TEST_IS_SYMLINK))
            break;
        g_free(t);
    }
    g_free(stem); g_free(ext); g_free(dir); g_free(base);
    return t;
}

static void on_restore(GtkButton *b, App *app)
{
    GPtrArray *keys = selected_keys(app);
    GString *errors = g_string_new(NULL);
    guint i;

    for (i = 0; i < keys->len; i++)
    {
        const char *key = keys->pdata[i];
        char *info = g_strdup_printf("%s/%s.trashinfo", app->info_dir, key);
        char *file = g_build_filename(app->files_dir, key, NULL);
        GKeyFile *kf = g_key_file_new();
        char *esc = NULL, *orig = NULL, *target = NULL, *parent;

        if (g_key_file_load_from_file(kf, info, G_KEY_FILE_NONE, NULL))
            esc = g_key_file_get_string(kf, "Trash Info", "Path", NULL);
        if (esc)
            orig = g_uri_unescape_string(esc, NULL);
        if (!orig || !g_path_is_absolute(orig))
        {
            g_string_append_printf(errors, "%s: the original location is not known\n", key);
            goto next;
        }
        target = free_target(orig);
        parent = g_path_get_dirname(target);
        g_mkdir_with_parents(parent, 0755);
        g_free(parent);
        if (g_rename(file, target) == 0)
            g_unlink(info);
        else
            g_string_append_printf(errors, "%s: %s\n", target, g_strerror(errno));
next:
        g_free(target); g_free(orig); g_free(esc);
        g_key_file_free(kf);
        g_free(file); g_free(info);
    }
    g_ptr_array_free(keys, TRUE);
    if (errors->len)
    {
        GtkWidget *d = gtk_message_dialog_new(GTK_WINDOW(app->win), GTK_DIALOG_MODAL,
                            GTK_MESSAGE_ERROR, GTK_BUTTONS_CLOSE, "Some items could not be restored:");
        gtk_message_dialog_format_secondary_text(GTK_MESSAGE_DIALOG(d), "%s", errors->str);
        gtk_window_set_title(GTK_WINDOW(d), "Trash");
        gtk_dialog_run(GTK_DIALOG(d));
        gtk_widget_destroy(d);
    }
    g_string_free(errors, TRUE);
    reload(app);
}

static void on_delete(GtkButton *b, App *app)
{
    GPtrArray *keys = selected_keys(app);
    char *q = keys->len == 1 ? g_strdup("Delete the selected item for good?")
                             : g_strdup_printf("Delete the %u selected items for good?", keys->len);
    if (keys->len && confirm(app, q, "_Delete"))
    {
        GPtrArray *args = g_ptr_array_new();
        guint i;
        g_ptr_array_add(args, (gpointer)"--delete");
        for (i = 0; i < keys->len; i++)
            g_ptr_array_add(args, keys->pdata[i]);
        run_purge(app, (const char *const *)args->pdata, args->len);
        g_ptr_array_free(args, TRUE);
    }
    g_free(q);
    g_ptr_array_free(keys, TRUE);
    reload(app);
}

static void on_empty(GtkButton *b, App *app)
{
    const char *args[] = { "--empty" };
    if (confirm(app, "Delete everything in the Trash for good?", "_Empty Trash"))
        run_purge(app, args, 1);
    reload(app);
}

static void on_age_changed(GtkComboBox *combo, App *app)
{
    int i = gtk_combo_box_get_active(combo);
    char months[4];
    const char *args[] = { "--set-months", months };
    if (i < 0 || i > 2)
        return;
    g_snprintf(months, sizeof months, "%d", ages[i]);
    run_purge(app, args, 2);
}

static int current_age_index(void)
{
    char *out = NULL;
    const char *argv[] = { "gobo-trash-purge", "--months", NULL };
    int m = 6, i;
    if (g_spawn_sync(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_STDERR_TO_DEV_NULL,
                     NULL, NULL, &out, NULL, NULL, NULL) && out)
        m = atoi(out);
    g_free(out);
    for (i = 0; i < 3; i++)
        if (ages[i] == m)
            return i;
    return 2;
}

static void on_selection_changed(GtkTreeSelection *s, App *app) { update_buttons(app); }

static GtkTreeViewColumn *text_column(const char *title, int col, int sort_col, gboolean expand)
{
    GtkCellRenderer *r = gtk_cell_renderer_text_new();
    GtkTreeViewColumn *c = gtk_tree_view_column_new_with_attributes(title, r, "text", col, NULL);
    g_object_set(r, "ellipsize", PANGO_ELLIPSIZE_END, NULL);
    gtk_tree_view_column_set_resizable(c, TRUE);
    gtk_tree_view_column_set_expand(c, expand);
    gtk_tree_view_column_set_sort_column_id(c, sort_col);
    return c;
}

static void on_activate(GtkApplication *gapp, App *app)
{
    GtkWidget *vbox, *scroll, *bbox, *hbox, *label;
    GtkTreeViewColumn *col;
    GtkCellRenderer *r;
    GtkTreeSelection *sel;
    GFile *gf;
    GList *wins = gtk_application_get_windows(gapp);

    if (wins)   /* already open: bring it up */
    {
        gtk_window_present(GTK_WINDOW(wins->data));
        return;
    }
    app->win = gtk_application_window_new(gapp);
    gtk_window_set_title(GTK_WINDOW(app->win), "Trash");
    gtk_window_set_icon_name(GTK_WINDOW(app->win), "user-trash");
    gtk_window_set_default_size(GTK_WINDOW(app->win), 720, 440);

    vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width(GTK_CONTAINER(vbox), 10);
    gtk_container_add(GTK_CONTAINER(app->win), vbox);

    app->store = gtk_list_store_new(N_COLS, G_TYPE_ICON, G_TYPE_STRING, G_TYPE_STRING,
                                    G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING);
    gtk_tree_sortable_set_sort_column_id(GTK_TREE_SORTABLE(app->store), COL_SORT, GTK_SORT_DESCENDING);
    app->view = gtk_tree_view_new_with_model(GTK_TREE_MODEL(app->store));
    col = gtk_tree_view_column_new();
    gtk_tree_view_column_set_title(col, "Name");
    r = gtk_cell_renderer_pixbuf_new();
    g_object_set(r, "stock-size", GTK_ICON_SIZE_LARGE_TOOLBAR, NULL);
    gtk_tree_view_column_pack_start(col, r, FALSE);
    gtk_tree_view_column_add_attribute(col, r, "gicon", COL_ICON);
    r = gtk_cell_renderer_text_new();
    g_object_set(r, "ellipsize", PANGO_ELLIPSIZE_END, NULL);
    gtk_tree_view_column_pack_start(col, r, TRUE);
    gtk_tree_view_column_add_attribute(col, r, "text", COL_NAME);
    gtk_tree_view_column_set_resizable(col, TRUE);
    gtk_tree_view_column_set_expand(col, TRUE);
    gtk_tree_view_column_set_sort_column_id(col, COL_NAME);
    gtk_tree_view_append_column(GTK_TREE_VIEW(app->view), col);
    /* fixed widths: the name takes what is left, the date always stays visible */
    col = text_column("Original folder", COL_ORIG_DIR, COL_ORIG_DIR, FALSE);
    gtk_tree_view_column_set_sizing(col, GTK_TREE_VIEW_COLUMN_FIXED);
    gtk_tree_view_column_set_fixed_width(col, 240);
    gtk_tree_view_append_column(GTK_TREE_VIEW(app->view), col);
    col = text_column("Deleted", COL_DATE, COL_SORT, FALSE);
    gtk_tree_view_column_set_min_width(col, 130);
    gtk_tree_view_append_column(GTK_TREE_VIEW(app->view), col);
    sel = gtk_tree_view_get_selection(GTK_TREE_VIEW(app->view));
    gtk_tree_selection_set_mode(sel, GTK_SELECTION_MULTIPLE);
    g_signal_connect(sel, "changed", G_CALLBACK(on_selection_changed), app);
    scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_shadow_type(GTK_SCROLLED_WINDOW(scroll), GTK_SHADOW_IN);
    gtk_container_add(GTK_CONTAINER(scroll), app->view);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);

    /* age setting */
    hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    label = gtk_label_new("Delete items automatically when they are older than");
    gtk_box_pack_start(GTK_BOX(hbox), label, FALSE, FALSE, 0);
    app->age_combo = gtk_combo_box_text_new();
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(app->age_combo), "1 month");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(app->age_combo), "3 months");
    gtk_combo_box_text_append_text(GTK_COMBO_BOX_TEXT(app->age_combo), "6 months");
    gtk_combo_box_set_active(GTK_COMBO_BOX(app->age_combo), current_age_index());
    g_signal_connect(app->age_combo, "changed", G_CALLBACK(on_age_changed), app);
    gtk_box_pack_start(GTK_BOX(hbox), app->age_combo, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), hbox, FALSE, FALSE, 0);

    /* buttons */
    bbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    app->status = gtk_label_new("");
    gtk_box_pack_start(GTK_BOX(bbox), app->status, FALSE, FALSE, 0);
    app->empty_btn = gtk_button_new_with_mnemonic("_Empty Trash");
    app->delete_btn = gtk_button_new_with_mnemonic("_Delete for good");
    app->restore_btn = gtk_button_new_with_mnemonic("_Restore");
    gtk_style_context_add_class(gtk_widget_get_style_context(app->restore_btn), "suggested-action");
    gtk_style_context_add_class(gtk_widget_get_style_context(app->empty_btn), "destructive-action");
    gtk_box_pack_end(GTK_BOX(bbox), app->restore_btn, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(bbox), app->delete_btn, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(bbox), app->empty_btn, FALSE, FALSE, 0);
    g_signal_connect(app->restore_btn, "clicked", G_CALLBACK(on_restore), app);
    g_signal_connect(app->delete_btn, "clicked", G_CALLBACK(on_delete), app);
    g_signal_connect(app->empty_btn, "clicked", G_CALLBACK(on_empty), app);
    gtk_box_pack_start(GTK_BOX(vbox), bbox, FALSE, FALSE, 0);

    /* follow changes (files deleted in PCManFM appear here at once) */
    g_mkdir_with_parents(app->info_dir, 0700);
    g_mkdir_with_parents(app->files_dir, 0700);
    gf = g_file_new_for_path(app->info_dir);
    app->monitor = g_file_monitor_directory(gf, G_FILE_MONITOR_NONE, NULL, NULL);
    g_object_unref(gf);
    if (app->monitor)
        g_signal_connect(app->monitor, "changed", G_CALLBACK(on_trash_changed), app);

    reload(app);
    gtk_widget_show_all(app->win);
}

int main(int argc, char **argv)
{
    App app = { 0 };
    GtkApplication *gapp;
    int status;

    app.trash = trash_dir();
    app.files_dir = g_build_filename(app.trash, "files", NULL);
    app.info_dir = g_build_filename(app.trash, "info", NULL);
    gapp = gtk_application_new("org.goborefined.Trash", G_APPLICATION_NON_UNIQUE);  /* no D-Bus needed */
    g_signal_connect(gapp, "activate", G_CALLBACK(on_activate), &app);
    status = g_application_run(G_APPLICATION(gapp), argc, argv);
    g_object_unref(gapp);
    return status;
}
