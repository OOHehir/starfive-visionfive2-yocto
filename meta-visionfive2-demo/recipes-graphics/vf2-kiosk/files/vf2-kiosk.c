/* vf2-kiosk — fullscreen WebKitGTK view of the local status webserver.
 *
 * Deliberately tiny: one fullscreen GTK4 window, one WebKitWebView, no
 * chrome, no navigation UI. The page itself (status.cgi) self-refreshes
 * and carries the touch controls. URL overridable via $KIOSK_URL.
 */
#include <gtk/gtk.h>
#include <webkit/webkit.h>

static const char *kiosk_url;

/* The status webserver may come up after us (sysvinit race) and lighttpd's
 * keep-alive handling can terminate an idle connection under libsoup — in
 * both cases WebKit would park on its error page forever (error pages don't
 * meta-refresh). Log the failure and retry until the page loads. */
static gboolean retry_load(gpointer data)
{
	webkit_web_view_load_uri(WEBKIT_WEB_VIEW(data), kiosk_url);
	return G_SOURCE_REMOVE;
}

static gboolean on_load_failed(WebKitWebView *view, WebKitLoadEvent ev,
			       char *failing_uri, GError *error,
			       gpointer user_data)
{
	g_printerr("vf2-kiosk: load failed (%s): %s — retrying in 2s\n",
		   failing_uri, error ? error->message : "?");
	g_timeout_add_seconds(2, retry_load, view);
	return TRUE;	/* suppress the built-in error page */
}

static void on_load_changed(WebKitWebView *view, WebKitLoadEvent ev,
			    gpointer user_data)
{
	if (ev == WEBKIT_LOAD_FINISHED)
		g_printerr("vf2-kiosk: load finished: %s\n",
			   webkit_web_view_get_uri(view));
}

static void activate(GtkApplication *app, gpointer user_data)
{
	GtkWidget *win = gtk_application_window_new(app);
	WebKitWebView *view = WEBKIT_WEB_VIEW(webkit_web_view_new());

	/* Panel is portrait-mounted; the desktop is landscape via weston's
	 * output transform, so no rotation needed here. */
	gtk_window_set_child(GTK_WINDOW(win), GTK_WIDGET(view));
	g_signal_connect(view, "load-failed", G_CALLBACK(on_load_failed), NULL);
	g_signal_connect(view, "load-changed", G_CALLBACK(on_load_changed), NULL);
	webkit_web_view_load_uri(view, kiosk_url);
	gtk_window_fullscreen(GTK_WINDOW(win));
	gtk_window_present(GTK_WINDOW(win));
}

int main(int argc, char **argv)
{
	GtkApplication *app;
	int status;

	kiosk_url = g_getenv("KIOSK_URL");
	if (!kiosk_url)
		kiosk_url = "http://127.0.0.1/status.cgi";

	app = gtk_application_new("org.visionfive2.kiosk",
				  G_APPLICATION_DEFAULT_FLAGS);
	g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
	status = g_application_run(G_APPLICATION(app), argc, argv);
	g_object_unref(app);
	return status;
}
