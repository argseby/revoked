#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* window_channel;
};

// Dart draws the title bar, so it needs to ask the window for the things a
// title bar does: move, minimize, maximize, close.
static const char* kWindowChannel = "revoked/window";

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// GTK keeps the client-side frame — shadow, rounded corners, resize edges —
// but nothing is drawn in the title bar slot, so the app's own top bar is the
// window's top edge instead of a second bar below the desktop's.
static void hide_title_bar(GtkWindow* window) {
  GtkWidget* titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_size_request(titlebar, 0, 0);
  gtk_widget_show(titlebar);
  gtk_window_set_titlebar(window, titlebar);

  // The theme styles whatever sits in that slot as a title bar, so a bare box
  // still draws its background and bottom border. Flatten it.
  g_autoptr(GtkCssProvider) css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css,
                                  "window.csd > .titlebar:not(headerbar) {"
                                  "  min-height: 0; padding: 0; margin: 0;"
                                  "  border: none; background: none;"
                                  "  box-shadow: none;"
                                  "}",
                                  -1, nullptr);
  gtk_style_context_add_provider_for_screen(
      gtk_window_get_screen(window), GTK_STYLE_PROVIDER(css),
      GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
}

// Hand the drag to the window manager from wherever the pointer currently is.
// Flutter reports positions inside the view, and begin_move_drag wants root
// coordinates, so ask the pointer itself rather than translating.
static void begin_move_drag(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr) {
    return;
  }
  GdkDevice* pointer = gdk_seat_get_pointer(
      gdk_display_get_default_seat(gdk_window_get_display(gdk_window)));
  if (pointer == nullptr) {
    return;
  }
  gint x = 0;
  gint y = 0;
  gdk_device_get_position(pointer, nullptr, &x, &y);
  gtk_window_begin_move_drag(window, GDK_BUTTON_PRIMARY, x, y,
                             GDK_CURRENT_TIME);
}

static void window_method_call(FlMethodChannel* channel,
                               FlMethodCall* method_call,
                               gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (self->window == nullptr) {
    fl_method_call_respond_error(method_call, "no-window",
                                 "the window is already gone", nullptr,
                                 nullptr);
    return;
  }

  g_autoptr(FlValue) result = nullptr;
  if (g_strcmp0(method, "ownsTitleBar") == 0) {
    result =
        fl_value_new_bool(gtk_window_get_titlebar(self->window) != nullptr);
  } else if (g_strcmp0(method, "isMaximized") == 0) {
    result = fl_value_new_bool(gtk_window_is_maximized(self->window));
  } else if (g_strcmp0(method, "startDrag") == 0) {
    begin_move_drag(self->window);
    result = fl_value_new_null();
  } else if (g_strcmp0(method, "minimize") == 0) {
    gtk_window_iconify(self->window);
    result = fl_value_new_null();
  } else if (g_strcmp0(method, "toggleMaximize") == 0) {
    if (gtk_window_is_maximized(self->window)) {
      gtk_window_unmaximize(self->window);
    } else {
      gtk_window_maximize(self->window);
    }
    result = fl_value_new_null();
  } else if (g_strcmp0(method, "close") == 0) {
    gtk_window_close(self->window);
    result = fl_value_new_null();
  } else {
    g_autoptr(FlMethodResponse) unknown =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, unknown, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(method_call, response, nullptr);
}

// The window can be maximized from outside the app — a keyboard shortcut, a
// drag to the screen edge — so the button's glyph follows the window rather
// than the last press.
static gboolean window_state_cb(GtkWidget* widget, GdkEventWindowState* event,
                                gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if ((event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) == 0 ||
      self->window_channel == nullptr) {
    return FALSE;
  }
  g_autoptr(FlValue) maximized = fl_value_new_bool(
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0);
  fl_method_channel_invoke_method(self->window_channel, "maximizedChanged",
                                  maximized, nullptr, nullptr, nullptr);
  return FALSE;
}

static void window_destroy_cb(GtkWidget* widget, gpointer user_data) {
  MY_APPLICATION(user_data)->window = nullptr;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // No desktop title bar at all: the app's top bar carries the window's
  // buttons, so a header bar above it would be a second row of chrome doing
  // the same job.
  self->window = window;
  gtk_window_set_title(window, "Revoked");
  hide_title_bar(window);
  g_signal_connect(window, "window-state-event", G_CALLBACK(window_state_cb),
                   self);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);

  // Flutter's runner sets no icon, so the taskbar falls back to a generic
  // one. Prefer the icon shipped in the bundle - it works straight from an
  // extracted tarball - and fall back to the themed name that install.sh
  // registers under hicolor.
  {
    g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
    if (exe != nullptr) {
      g_autofree gchar* dir = g_path_get_dirname(exe);
      g_autofree gchar* icon =
          g_build_filename(dir, "data", "app_icon.png", nullptr);
      if (g_file_test(icon, G_FILE_TEST_EXISTS)) {
        gtk_window_set_icon_from_file(window, icon, nullptr);
      } else {
        gtk_window_set_default_icon_name("revoked");
      }
    } else {
      gtk_window_set_default_icon_name("revoked");
    }
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kWindowChannel,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_method_call, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // Deliberately not handled locally. Deferring to the default lets
  // GApplication deliver the arguments to the primary instance when one is
  // already running, which is how a revoked:// link reaches the open window
  // instead of starting a second copy that nothing is listening to.
  return FALSE;
}

// Implements GApplication::command_line. Runs in the primary instance, for
// its own launch and for every later one.
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);

  gint argc = 0;
  gchar** argv = g_application_command_line_get_arguments(command_line, &argc);
  if (argc > 1) {
    g_strfreev(self->dart_entrypoint_arguments);
    self->dart_entrypoint_arguments = g_strdupv(argv + 1);
  }
  g_strfreev(argv);

  // activate() builds a window and a Flutter engine every time it is called,
  // so a second launch must not go through it — the link has already been
  // delivered to the running instance by the command-line signal above.
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return 0;
  }

  g_application_activate(application);
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->window_channel);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
