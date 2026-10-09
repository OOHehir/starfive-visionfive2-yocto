/* Fullscreen WebKitGTK view of the status page, which carries its own
 * refresh & touch controls. URL overridable via $KIOSK_URL. */
#include <gtk/gtk.h>
#include <webkit/webkit.h>

static const char *kiosk_url;

/* lighttpd may start after us or drop an idle keep-alive, & WebKit's error
 * page never refreshes, so retry until the page loads. */
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

	/* No rotation: weston's output transform already makes it landscape. */
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
