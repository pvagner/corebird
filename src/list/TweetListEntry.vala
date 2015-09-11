/*  This file is part of corebird, a Gtk+ linux Twitter client.
 *  Copyright (C) 2013 Timm Bäder
 *
 *  corebird is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  corebird is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with corebird.  If not, see <http://www.gnu.org/licenses/>.
 */


[GtkTemplate (ui = "/org/baedert/corebird/ui/tweet-list-entry.ui")]
public class TweetListEntry : ITwitterItem, Gtk.ListBoxRow {
  private const GLib.ActionEntry[] action_entries = {
    {"quote", quote_activated},
    {"delete", delete_activated}
  };

  private const int64 TRANSITION_DURATION = 300;

  [GtkChild]
  private Gtk.Label screen_name_label;
  [GtkChild]
  private TextButton name_button;
  [GtkChild]
  private Gtk.Label time_delta_label;
  [GtkChild]
  private AvatarWidget avatar_image;
  [GtkChild]
  private Gtk.Label text_label;
  [GtkChild]
  private Gtk.Label rt_label;
  [GtkChild]
  private Gtk.Image rt_image;
  [GtkChild]
  private Gtk.Image conversation_image;
  [GtkChild]
  private Gtk.Image rt_status_image;
  [GtkChild]
  private Gtk.Image fav_status_image;
  [GtkChild]
  private DoubleTapButton retweet_button;
  [GtkChild]
  private Gtk.ToggleButton favorite_button;
  [GtkChild]
  private Gtk.Grid grid;
  [GtkChild]
  private MultiMediaWidget mm_widget;
  [GtkChild]
  private Gtk.Stack stack;
  [GtkChild]
  private Gtk.Box action_box;
  [GtkChild]
  private Gtk.Label quote_label;
  [GtkChild]
  private TextButton quote_name;
  [GtkChild]
  private Gtk.Label quote_screen_name;
  [GtkChild]
  private Gtk.Grid quote_grid;


  private bool _read_only = false;
  public bool read_only {
    set {
      mm_widget.sensitive = !value;
      name_button.read_only = value;
      this._read_only = value;
    }
  }
  public new bool visible {
    get {
      return !this.tweet.is_hidden;
    }
    set {
      base.visible = value;
    }
  }
  public int64 sort_factor {
    get { return tweet.source_tweet.id;}
  }
  public bool shows_actions {
    get {
      return stack.visible_child == action_box;
    }
  }
  private weak Account account;
  private weak MainWindow main_window;
  public Tweet tweet;
  private bool values_set = false;
  private bool delete_first_activated = false;
  [Signal (action = true)]
  private signal void reply_tweet ();
  [Signal (action = true)]
  private signal void favorite_tweet ();
  [Signal (action = true)]
  private signal void retweet_tweet ();
  [Signal (action = true)]
  private signal void delete_tweet ();

  public TweetListEntry (owned Tweet tweet, MainWindow? main_window, Account account) {
    this.account = account;
    this.tweet = tweet;
    this.main_window = main_window;

    name_button.set_markup (tweet.user_name);
    screen_name_label.label = "@" + tweet.screen_name;
    avatar_image.surface = tweet.avatar;
    avatar_image.verified = tweet.verified;
    text_label.label = tweet.get_trimmed_text ();
    update_time_delta ();
    if (tweet.retweeted_tweet != null) {
      rt_label.show ();
      rt_image.show ();
      rt_label.label = @"<span underline='none'><a href=\"@$(tweet.source_tweet.author.id)/" +
                       @"@$(tweet.source_tweet.author.screen_name)\"" +
                       @"title=\"@$(tweet.source_tweet.author.screen_name)\">" +
                       @"$(tweet.source_tweet.author.user_name)</a></span>";
    } else {
      grid.remove (rt_image);
      grid.remove (rt_label);
    }

    if (tweet.quoted_tweet != null) {
      quote_label.label = TextTransform.transform_tweet (tweet.quoted_tweet,
                                                         Settings.get_text_transform_flags ());
      quote_name.set_markup (tweet.quoted_tweet.author.user_name);
      quote_screen_name.label = "@" + tweet.quoted_tweet.author.screen_name;

      quote_grid.show ();
      quote_grid.show_all ();
    }

    retweet_button.active = tweet.retweeted;
    retweet_button.sensitive = (tweet.user_id != account.id) &&
                               !tweet.protected;
    tweet.notify["retweeted"].connect (retweeted_cb);

    favorite_button.active = tweet.favorited;
    tweet.notify["favorited"].connect (favorited_cb);

    tweet.hidden_flags_changed.connect (hidden_flags_changed_cb);
    tweet.notify["deleted"].connect (tweet_deleted_cb);

    if (tweet.reply_id == 0)
      conversation_image.unparent ();
    else {
      conversation_image.show ();
    }

    // If the avatar gets loaded, we want to change it here immediately
    tweet.notify["avatar"].connect (avatar_changed);

    if (tweet.has_inline_media) {
      mm_widget.set_all_media (tweet.medias);
      mm_widget.media_clicked.connect (media_clicked_cb);
      mm_widget.media_invalid.connect (media_invalid_cb);
      mm_widget.window = main_window;
    } else
      grid.remove (mm_widget);


    var actions = new GLib.SimpleActionGroup ();
    actions.add_action_entries (action_entries, this);
    this.insert_action_group ("tweet", actions);

    if (tweet.user_id != account.id)
      ((GLib.SimpleAction)actions.lookup_action ("delete")).set_enabled (false);

    if (tweet.user_id == account.id ||
        tweet.protected)
      ((GLib.SimpleAction)actions.lookup_action ("quote")).set_enabled (false);

    reply_tweet.connect (reply_tweet_activated);
    delete_tweet.connect (delete_tweet_activated);
    favorite_tweet.connect (() => {
      if (favorite_button.parent != null)
        favorite_button.active = !favorite_button.active;
    });
    retweet_tweet.connect (() => {
      retweet_button.tap ();
    });

    if (tweet.favorited)
      fav_status_image.show ();

    if (tweet.retweeted)
      rt_status_image.show ();

    values_set = true;

    Settings.get ().changed["text-transform-flags"].connect (transform_flags_changed_cb);
  }

  ~TweetListEntry () {
    Settings.get ().changed["text-transform-flags"].disconnect (transform_flags_changed_cb);
  }

  private void transform_flags_changed_cb () {
    text_label.label = tweet.get_trimmed_text ();
    if (this.tweet.quoted_tweet != null) {
      this.quote_label.label = TextTransform.transform_tweet (tweet.quoted_tweet,
                                                              Settings.get_text_transform_flags ());
    }
  }

  private void favorited_cb () {
    values_set = false;
    favorite_button.active = tweet.favorited;
    fav_status_image.visible = tweet.favorited;
    values_set = true;
  }

  private void retweeted_cb () {
    values_set = false;
    retweet_button.active = tweet.retweeted;
    rt_status_image.visible = tweet.retweeted;
    values_set = true;
  }

  private void media_clicked_cb (Media m, int index) {
    TweetUtils.handle_media_click (this.tweet, this.main_window, index);
  }

  private void delete_tweet_activated () {
    if (tweet.user_id != account.id)
      return; // Nope.

    if (delete_first_activated) {
      TweetUtils.delete_tweet.begin (account, tweet, () => {
        sensitive = false;
      });
    } else
      delete_first_activated = true;
  }

  private void avatar_changed () {
    avatar_image.surface = tweet.avatar;
  }

  static construct {
    unowned Gtk.BindingSet binding_set = Gtk.BindingSet.by_class ((GLib.ObjectClass)typeof (TweetListEntry).class_ref ());

    Gtk.BindingEntry.add_signal (binding_set, Gdk.Key.r, 0, "reply-tweet", 0, null);
    Gtk.BindingEntry.add_signal (binding_set, Gdk.Key.d, 0, "delete-tweet", 0, null);
    Gtk.BindingEntry.add_signal (binding_set, Gdk.Key.t, 0, "retweet-tweet", 0, null);
    Gtk.BindingEntry.add_signal (binding_set, Gdk.Key.f, 0, "favorite-tweet", 0, null);
  }

  [GtkCallback]
  private bool focus_out_cb (Gdk.EventFocus evt) {
    delete_first_activated = false;
    retweet_button.reset ();
    return false;
  }


  [GtkCallback]
  private bool key_released_cb (Gdk.EventKey evt) {
#if DEBUG
    switch(evt.keyval) {
      case Gdk.Key.k:
        stdout.printf (tweet.json_data+"\n");
        return true;
    }
#endif
    return false;
  }

  /**
   * Retweets or un-retweets the tweet.
   */
  [GtkCallback]
  private void retweet_button_toggled_cb () {
    /* You can't retweet your own tweets. */
    if (account.id == this.tweet.user_id || !values_set) {
      retweet_button.active = false;
      return;
    }

    retweet_button.sensitive = false;
    TweetUtils.toggle_retweet_tweet.begin (account, tweet, !retweet_button.active, () => {
      retweet_button.sensitive = true;
    });
    if (shows_actions)
      toggle_mode ();
  }

  [GtkCallback]
  private void favorite_button_toggled_cb () {
    if (!values_set)
      return;

    favorite_button.sensitive = false;
    TweetUtils.toggle_favorite_tweet.begin (account, tweet, !favorite_button.active, () => {
      favorite_button.sensitive = true;
    });
    if (shows_actions)
      toggle_mode ();
  }

  [GtkCallback]
  private void name_button_clicked_cb () {
    int64 user_id;
    string screen_name;

    if (tweet.retweeted_tweet != null) {
      user_id = tweet.retweeted_tweet.author.id;
      screen_name = tweet.retweeted_tweet.author.screen_name;
    } else {
      user_id = tweet.source_tweet.author.id;
      screen_name = tweet.source_tweet.author.screen_name;
    }

    var bundle = new Bundle ();
    bundle.put_int64 ("user_id", user_id);
    bundle.put_string ("screen_name", screen_name);
    main_window.main_widget.switch_page (Page.PROFILE, bundle);
  }

  [GtkCallback]
  private void quote_name_button_clicked_cb () {
    assert (tweet.quoted_tweet != null);
    var bundle = new Bundle ();
    bundle.put_int64 ("user_id", tweet.quoted_tweet.author.id);
    bundle.put_string ("screen_name", tweet.quoted_tweet.author.screen_name);
    main_window.main_widget.switch_page (Page.PROFILE, bundle);
  }


  [GtkCallback]
  private void reply_button_clicked_cb () {
    ComposeTweetWindow ctw = new ComposeTweetWindow (this.main_window, this.account, this.tweet,
                                                     ComposeTweetWindow.Mode.REPLY);
    ctw.show ();
    if (shows_actions)
      toggle_mode ();
  }

  private void quote_activated () {
    ComposeTweetWindow ctw = new ComposeTweetWindow (this.main_window, this.account, this.tweet,
                                                     ComposeTweetWindow.Mode.QUOTE);
    ctw.show ();
    toggle_mode ();
  }

  private void reply_tweet_activated () {
    ComposeTweetWindow ctw = new ComposeTweetWindow (this.main_window, this.account, this.tweet,
                                                     ComposeTweetWindow.Mode.REPLY);
    ctw.show ();
  }

  private void delete_activated () {
    delete_first_activated = true;
    delete_tweet ();
    toggle_mode ();
  }

  [GtkCallback]
  private bool link_activated_cb (string uri) {
    if (this._read_only) {
      return false;
    }

    this.grab_focus ();

    return TweetUtils.activate_link (uri, main_window);
  }

  [GtkCallback]
  private void populate_popup_cb (Gtk.Label source, Gtk.Menu menu) {
    var link_text = source.get_current_uri ();
    if (link_text.has_prefix ("#")) {
      var item = new Gtk.MenuItem.with_label (_("Block %s").printf (link_text));
      item.show ();
      item.activate.connect (() => {
        Utils.create_persistent_filter (link_text, account);
        main_window.rerun_filters ();
      });
      menu.add (item);
    }
  }

  private void media_invalid_cb () {
    TransformFlags flags = Settings.get_text_transform_flags ()
                           & ~TransformFlags.REMOVE_MEDIA_LINKS;
    string new_text = TextTransform.transform_tweet (tweet.retweeted_tweet ?? tweet.source_tweet,
                                                     flags);
    this.text_label.label = new_text;

    if (tweet.quoted_tweet != null) {
      string new_quote_text = TextTransform.transform_tweet (tweet.quoted_tweet,
                                                             flags);
      this.quote_label.label = new_quote_text;
    }
  }

  private void hidden_flags_changed_cb () {
    if (tweet.is_hidden)
      this.hide ();
    else
      this.show ();
  }

  private void tweet_deleted_cb () {
#if DEBUG
    assert (this.sensitive != tweet.deleted);
#endif

    this.sensitive = !tweet.deleted;
    stack.visible_child = grid;
  }


  /**
   * Updates the time delta label in the upper right
   *
   * @return The seconds between the current time and
   *         the time the tweet was created
   */
  public int update_time_delta (GLib.DateTime? now = null) { //{{{
    GLib.DateTime cur_time;
    if (now == null)
      cur_time = new GLib.DateTime.now_local ();
    else
      cur_time = now;

    GLib.DateTime then = new GLib.DateTime.from_unix_local (
                             tweet.retweeted_tweet != null ? tweet.retweeted_tweet.created_at :
                                                             tweet.source_tweet.created_at);
                 //tweet.is_retweet ? tweet.rt_created_at : tweet.created_at);
    time_delta_label.label = Utils.get_time_delta (then, cur_time);
    return (int)(cur_time.difference (then) / 1000.0 / 1000.0);
  } //}}}


  public void toggle_mode () {
    if (this._read_only)
      return;

    if (stack.visible_child == action_box) {
      stack.visible_child = grid;
      this.activatable = true;
    } else {
      stack.visible_child = action_box;
      this.activatable = false;
    }
  }


  private int64 start_time;
  private int64 end_time;

  private double ease_out_cubic (double t) {
    double p = t - 1;
    return p * p * p +1;
  }

  private bool anim_tick (Gtk.Widget widget, Gdk.FrameClock frame_clock) {
    int64 now = frame_clock.get_frame_time ();

    if (now > end_time) {
      this.opacity = 1.0;
      return false;
    }

    double t = (now - start_time) / (double)(end_time - start_time);

    t = ease_out_cubic (t);

    this.opacity = t;

    return true;
  }

  public void fade_in () {
    if (this.get_realized ()) {
      this.show ();
      return;
    }

    ulong realize_id = 0;
    realize_id = this.realize.connect (() => {
      this.start_time = this.get_frame_clock ().get_frame_time ();
      this.end_time = start_time + (TRANSITION_DURATION * 1000);
      this.add_tick_callback (anim_tick);
      this.disconnect (realize_id);
    });

    this.show ();
  }

  public override void show () {
    if (tweet.is_hidden)
      return;

    base.show ();
  }
}
