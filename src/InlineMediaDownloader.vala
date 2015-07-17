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


namespace InlineMediaDownloader {

  public async void load_media (Tweet t, Media media) {
    yield load_inline_media (t, media);
  }

  public void load_all_media (Tweet t, Media[] medias) {
    foreach (Media m in medias) {
      load_media.begin (t, m);
    }
  }

  private static void mark_invalid (Media              m) {
    m.invalid = true;
    m.loaded = true;
    m.finished_loading ();
  }

  public bool is_media_candidate (string url) {
    if (Settings.max_media_size () < 0.001)
      return false;

    return url.has_prefix ("http://instagra.am") ||
           url.has_prefix ("http://instagram.com/p/") ||
           url.has_prefix ("https://instagr.am") ||
           url.has_prefix ("https://instagram.com/p/") ||
           url.has_prefix ("http://i.imgur.com") ||
           url.has_prefix ("http://d.pr/i/") ||
           url.has_prefix ("http://ow.ly/i/") ||
           url.has_prefix ("http://www.flickr.com/photos/") ||
           url.has_prefix ("https://www.flickr.com/photos/") ||
#if VIDEO
           url.has_prefix ("https://vine.co/v/") ||
           url.has_suffix ("/photo/1") ||
           url.has_prefix ("https://video.twimg.com/ext_tw_video/") ||
#endif
           url.has_prefix ("http://pbs.twimg.com/media/") ||
           url.has_prefix ("http://twitpic.com/")
    ;
  }

  // XXX Rename
  private async void load_real_url (Tweet  t,
                                    Media  media,
                                    string regex_str1,
                                    int    match_index1) {
    var msg = new Soup.Message ("GET", media.url);
    SOUP_SESSION.queue_message (msg, (_s, _msg) => {
      string? back = (string)_msg.response_body.data;
      if (msg.status_code != Soup.Status.OK) {
        warning ("Message status: %s", msg.status_code.to_string ());
        mark_invalid (media);
        return;
      }

      if (back == null) {
        warning ("Url '%s' returned null", media.url);
        mark_invalid (media);
        return;
      }
      try {
        var regex = new GLib.Regex (regex_str1, 0);
        MatchInfo info;
        regex.match (back, 0, out info);
        string real_url = info.fetch (match_index1);
        media.thumb_url = real_url;

        load_real_url.callback ();
      } catch (GLib.RegexError e) {
        critical ("Regex Error(%s): %s", regex_str1, e.message);
      }
    });
    yield;
  }

  private async void load_inline_media (Tweet t, Media media) {
    GLib.SourceFunc callback = load_inline_media.callback;

    string ext = Utils.get_file_type (media.url);
    {
      if(ext.length == 0)
        ext = "png";

      ext = ext.down();
      int qm_index;
      if ((qm_index = ext.index_of_char ('?')) != -1) {
        ext = ext.substring (0, qm_index);
      }

      if (ext == "jpg")
        ext = "jpeg";
    }

    /* If we get to this point, the image was not cached on disk and we
       *really* need to download it. */
    string url = media.url;
    if (url.has_prefix ("http://instagr.am") ||
        url.has_prefix ("http://instagram.com/p/") ||
        url.has_prefix ("https://instagr.am") ||
        url.has_prefix ("https://instagram.com/p/") ||
        url.has_prefix ("http://ow.ly/i/") ||
        url.has_prefix ("https://ow.ly/i/") ||
        url.has_prefix ("http://www.flickr.com/photos/") ||
        url.has_prefix ("https://www.flickr.com/photos/")) {
      yield load_real_url (t, media, "<meta property=\"og:image\" content=\"(.*?)\"", 1);
    } else if (url.has_prefix("http://twitpic.com/")) {
      yield load_real_url (t, media,
                          "<meta name=\"twitter:image\" value=\"(.*?)\"", 1);
    } else if (url.has_prefix ("https://vine.co/v/")) {
      yield load_real_url (t, media, "<meta property=\"og:image\" content=\"(.*?)\"", 1);
    } else if (url.has_suffix ("/photo/1")) {
      yield load_real_url (t, media, "<img src=\"(.*?)\" class=\"animated-gif-thumbnail", 1);
    } else if (url.has_prefix ("http://d.pr/i/")) {
      yield load_real_url (t, media,
                          "<meta property=\"og:image\"\\s+content=\"(.*?)\"", 1);
    }


    var msg = new Soup.Message ("GET", media.thumb_url);
    msg.got_headers.connect (() => {
      int64 content_length = msg.response_headers.get_content_length ();
      double mb = content_length / 1024.0 / 1024.0;
      double max = Settings.max_media_size ();
      if (mb > max) {
        debug ("Image %s won't be downloaded,  %fMB > %fMB", media.thumb_url, mb, max);
        mark_invalid (media);
        SOUP_SESSION.cancel_message (msg, Soup.Status.CANCELLED);
      } else {
        media.length = content_length;
      }
    });

    msg.got_chunk.connect ((buf) => {
      double percent = (double) buf.length / (double) media.length;
      media.percent_loaded += percent;
    });


    SOUP_SESSION.queue_message(msg, (s, _msg) => {
      if (_msg.status_code != Soup.Status.OK) {
        mark_invalid (media);
        callback ();
        return;
      }

      var ms = new MemoryInputStream.from_data (_msg.response_body.data, null);
      if (ext == "gif") {
        load_animation.begin (t, ms, media, () => {
          callback ();
        });
      } else {
        load_normal_media.begin (t, ms, media, () => {
          callback ();
        });
      }
      yield;
    });
    yield;
  }

  private async void load_animation (Tweet                  t,
                                     GLib.MemoryInputStream in_stream,
                                     Media                  media) {
    Gdk.PixbufAnimation anim;
    try {
      anim = yield new Gdk.PixbufAnimation.from_stream_async (in_stream, null);
    } catch (GLib.Error e) {
      warning (e.message);
      mark_invalid (media);//, in_stream, thumb_out_stream);
      return;
    }
    var pic = anim.get_static_image ();
    media.thumbnail = Gdk.cairo_surface_create_from_pixbuf (pic, 1, null);
    media.loaded = true;
    media.finished_loading ();
    try {
      in_stream.close ();
    } catch (GLib.Error e) {
      warning (e.message);
    }

  }

  private async void load_normal_media (Tweet             t,
                                        GLib.InputStream  in_stream,
                                        Media             media) {
    Gdk.Pixbuf pic = null;
    try {
      pic = yield new Gdk.Pixbuf.from_stream_async (in_stream, null);
    } catch (GLib.Error e) {
      warning ("%s(%s)", e.message, media.path);
      mark_invalid (media);//, in_stream, thumb_out_stream);
      return;
    }


    media.thumbnail = Gdk.cairo_surface_create_from_pixbuf (pic, 1, null);
    media.loaded = true;
    media.finished_loading ();
    try {
      in_stream.close ();
      //thumb_out_stream.close ();
    } catch (GLib.Error e) {
      warning (e.message);
    }
  }

}
