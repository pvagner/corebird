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

public struct UserIdentity {
  int64 id;
  string screen_name;
  string user_name;
}

UserIdentity? parse_identity (Json.Object user_obj)
{
  UserIdentity id = {};
  id.id = user_obj.get_int_member ("id");
  id.screen_name = user_obj.get_string_member ("screen_name");
  id.user_name = user_obj.get_string_member ("name").replace ("&", "&amp;").strip ();

  return id;
}

// XXX FUCK THIS SHOULD BE A STRUCT FFS
public class MiniTweet {
  public int64 id;
  public int64 created_at;
  public UserIdentity author;
  public string text;
  public TextEntity[] entities;
  public Media[] medias;
}

MiniTweet? parse_mini_tweet (Json.Object status)
{
  MiniTweet mt = new MiniTweet ();
  mt.id = status.get_int_member ("id");
  mt.author = parse_identity (status.get_object_member ("user"));
  mt.text = status.get_string_member ("text");
  mt.created_at = Utils.parse_date (status.get_string_member ("created_at")).to_unix ();

  return mt;
}

void parse_entities (MiniTweet mt, Json.Object status)
{ // {{{
  var entities = status.get_object_member ("entities");
  var urls = entities.get_array_member("urls");
  var hashtags = entities.get_array_member ("hashtags");
  var user_mentions = entities.get_array_member ("user_mentions");

  int media_count = Utils.get_json_array_size (entities, "media");
  if (status.has_member ("extended_entities"))
    media_count += Utils.get_json_array_size (status.get_object_member ("extended_entities"), "media");

  media_count += (int)urls.get_length ();

  mt.medias = new Media[media_count];
  int real_media_count = 0;

  /* Overallocate here, remove the unnecessary parts later. */
  mt.entities = new TextEntity[urls.get_length () +
                               hashtags.get_length () +
                               user_mentions.get_length () +
                               media_count];

  int url_index = 0;


  urls.foreach_element((arr, index, node) => {
    var url = node.get_object();
    string expanded_url = url.get_string_member("expanded_url");

    if (InlineMediaDownloader.is_media_candidate (expanded_url)) {
      var m = new Media ();
      m.url = expanded_url;
      m.id = real_media_count;
      m.type = Media.type_from_url (expanded_url);
      mt.medias[real_media_count] = m;
      real_media_count ++;
    }

    Json.Array indices = url.get_array_member ("indices");
    expanded_url = expanded_url.replace("&", "&amp;");
    mt.entities[url_index] = TextEntity () {
      from = (uint) indices.get_int_element (0),
      to   = (uint) indices.get_int_element (1),
      display_text = url.get_string_member ("display_url"),
      tooltip_text = expanded_url,
      target = expanded_url
    };
    url_index ++;
  });

  hashtags.foreach_element ((arr, index, node) => {
    var hashtag = node.get_object ();
    Json.Array indices = hashtag.get_array_member ("indices");
    mt.entities[url_index] = TextEntity () {
      from = (uint) indices.get_int_element (0),
      to   = (uint) indices.get_int_element (1),
      display_text = "#" + hashtag.get_string_member ("text"),
      tooltip_text = "#" + hashtag.get_string_member ("text"),
      target = null // == display_text
    };
    url_index ++;
  });


  user_mentions.foreach_element ((arr, index, node) => {
    var mention = node.get_object ();
    Json.Array indices = mention.get_array_member ("indices");

    string screen_name = mention.get_string_member ("screen_name");
    mt.entities[url_index] = TextEntity () {
      from = (uint) indices.get_int_element (0),
      to   = (uint) indices.get_int_element (1),
      display_text = "@" + screen_name,
      target = "@" + mention.get_string_member ("id_str") + "/@" + screen_name,
      tooltip_text = mention.get_string_member ("name")
    };
    url_index ++;
  });

  // The same with media
  if (entities.has_member ("media")) {
    var medias = entities.get_array_member ("media");
    medias.foreach_element ((arr, index, node) => {
      var url = node.get_object();
      string expanded_url = url.get_string_member ("expanded_url");
      expanded_url = expanded_url.replace ("&", "&amp;");
      Json.Array indices = url.get_array_member ("indices");
      mt.entities[url_index] = TextEntity () {
        from = (uint) indices.get_int_element (0),
        to   = (uint) indices.get_int_element (1),
        target = url.get_string_member ("url"),
        display_text = url.get_string_member ("display_url")
      };
      url_index ++;
      string media_url = url.get_string_member ("media_url");
      if (InlineMediaDownloader.is_media_candidate (media_url)) {
        var m = new Media ();
        m.url = media_url;
        m.target_url = media_url + ":large";
        mt.medias[real_media_count] = m;
        real_media_count ++;
      }
    });
  }

  if (status.has_member ("extended_entities")) {
    var extended_entities = status.get_object_member ("extended_entities");
    var extended_media = extended_entities.get_array_member ("media");
    extended_media.foreach_element ((arr, index, node) => {
      var media_obj = node.get_object ();
      string media_type = media_obj.get_string_member ("type");
      if (media_type == "photo") {
        string url = media_obj.get_string_member ("media_url");
        foreach (Media m in mt.medias) {
          if (m != null && m.url == url)
            return;
        }
        if (InlineMediaDownloader.is_media_candidate (url)) {
          var m = new Media ();
          m.url = url;
          m.target_url = url + ":large";
          m.id = media_obj.get_int_member ("id");
          m.type = Media.type_from_string (media_obj.get_string_member ("type"));
          mt.medias[real_media_count] = m;
          real_media_count ++;
        }
      } else if (media_type == "video" ||
                 media_type == "animated_gif") {
        Json.Object? variant = null;
        Json.Array variants = media_obj.get_object_member ("video_info")
                                       .get_array_member ("variants");

        /* Just pick the first mp4 variant */
        for (uint i = 0; i < variants.get_length (); i ++) {
          variant = variants.get_element (i).get_object ();
          if (variant.get_string_member ("content_type") == "video/mp4")
            break;
        }

        if (variant != null) {
          Media m = new Media ();
          m.url = variant.get_string_member ("url");
          m.thumb_url = media_obj.get_string_member ("media_url");
          m.type = MediaType.TWITTER_VIDEO;
          m.id = media_obj.get_int_member ("id");
          mt.medias[real_media_count] = m;
          real_media_count ++;
        }
      }
    });
  }

  mt.medias.resize (real_media_count);
  InlineMediaDownloader.load_all_media (mt, mt.medias);

  /* Remove unnecessary url entries */
  mt.entities.resize (url_index);
  TweetUtils.sort_entities (ref mt.entities);

} // }}}


public class Tweet : GLib.Object {
  public static const int MAX_LENGTH = 140;

  /** Force hiding (there's no way this flag will ever get flipped...)*/
  public const uint HIDDEN_FORCE             = 1 << 0;
  /** Hidden because we unfolled the author */
  public const uint HIDDEN_UNFOLLOWED        = 1 << 1;
  /** Hidden because one of the filters matched the tweet */
  public const uint HIDDEN_FILTERED          = 1 << 2;
  /** Hidden because RTs of the author are disabled */
  public const uint HIDDEN_RTS_DISABLED      = 1 << 3;
  /** Hidden because it's a RT by the authenticating user */
  public const uint HIDDEN_RT_BY_USER        = 1 << 4;
  public const uint HIDDEN_RT_BY_FOLLOWEE    = 1 << 5;
  /** Hidden because the author is blocked */
  public const uint HIDDEN_AUTHOR_BLOCKED    = 1 << 6;
  /** Hidden because the author of a retweet is blocked */
  public const uint HIDDEN_RETWEETER_BLOCKED = 1 << 7;

  public uint hidden_flags = 0;

#if DEBUG
  public string json_data;
#endif

  public bool is_hidden {
    get {
      return hidden_flags > 0;
    }
  }
  public signal void hidden_flags_changed ();

  public int64 id;
  public bool retweeted { get; set; default = false; }
  public bool favorited { get; set; default = false; }
  public bool deleted   { get; set; default = false; }

  public int64 user_id {
    get {
      if (this.retweeted_tweet != null)
        return this.retweeted_tweet.author.id;
      else
        return this.source_tweet.author.id;
    }
  }
  public string screen_name {
   get {
      if (this.retweeted_tweet != null)
        return this.retweeted_tweet.author.screen_name;
      else
        return this.source_tweet.author.screen_name;
    }
  }
  public string user_name {
    get {
      if (this.retweeted_tweet != null)
        return this.retweeted_tweet.author.user_name;
      else
        return this.source_tweet.author.user_name;
    }
  }
  public MiniTweet  source_tweet;
  public MiniTweet? retweeted_tweet = null;
  public MiniTweet? quoted_tweet = null;

  public Cairo.Surface avatar { get; set; }
  /** The avatar url on the server */
  public string avatar_url;
  public bool verified = false;
  public int64 my_retweet;
  public bool protected;
  public string? notification_id = null;
  private bool _seen = true;
  public bool seen {
    get {
      return _seen;
    }
    set {
      _seen = value;
      if (value && notification_id != null) {
        NotificationManager.withdraw (this.notification_id);
        this.notification_id = null;
      }
    }
  }

  /** if 0, this tweet is NOT part of a conversation */
  public int64 reply_id = 0;

  public Media[] medias {
    get {
      if (this.retweeted_tweet != null)
        return this.retweeted_tweet.medias;
      else if (this.quoted_tweet != null)
        return this.quoted_tweet.medias;
      else
        return this.source_tweet.medias;
    }
  }
  public bool has_inline_media {
    get {
      if (this.retweeted_tweet != null)
        return retweeted_tweet.medias != null &&
               retweeted_tweet.medias.length > 0;
      else if (this.quoted_tweet != null)
        return quoted_tweet.medias != null &&
               quoted_tweet.medias.length > 0;
      else
        return source_tweet.medias != null &&
               source_tweet.medias.length > 0;
    }
  }

  public int retweet_count;
  public int favorite_count;

  public Tweet () {
    this.avatar = Twitter.no_avatar;
  }

  public string[] get_mentions () {
    TextEntity[] entities;
    if (this.retweeted_tweet != null)
      entities = this.retweeted_tweet.entities;
    else
      entities = this.source_tweet.entities;


    string[] e = new string[entities.length];
    int n_mentions = 0;
    foreach (var entity in entities) {
      if (entity.display_text[0] == '@') {
        e[n_mentions] = entity.display_text;
        n_mentions ++;
      }
    }

    e.resize (n_mentions);
    return e;
  }


  /**
   * Fills all the data of this tweet from Json data.
   * @param status The Json object to get the data from
   * @param now The current time
   */
  public void load_from_json (Json.Node     status_node,
                              GLib.DateTime now,
                              Account       account) {
    Json.Object status = status_node.get_object ();
    Json.Object user = status.get_object_member("user");
    this.id          = status.get_int_member("id");
    this.favorited   = status.get_boolean_member("favorited");
    this.retweeted   = status.get_boolean_member("retweeted");
    this.retweet_count = (int)status.get_int_member ("retweet_count");
    this.favorite_count = (int)status.get_int_member ("favorite_count");

    this.source_tweet = parse_mini_tweet (status);

    if (status.has_member("retweeted_status")) {
      Json.Object rt      = status.get_object_member("retweeted_status");
      this.retweeted_tweet = parse_mini_tweet (rt);
      parse_entities (this.retweeted_tweet, rt);

      Json.Object rt_user = rt.get_object_member("user");
      this.avatar_url    = rt_user.get_string_member ("profile_image_url");
      this.verified      = rt_user.get_boolean_member ("verified");
      this.protected     = rt_user.get_boolean_member ("protected");
      if (!rt.get_null_member ("in_reply_to_status_id"))
        this.reply_id = rt.get_int_member ("in_reply_to_status_id");
    } else {
      parse_entities (this.source_tweet, status);
      this.avatar_url  = user.get_string_member ("profile_image_url");
      this.verified    = user.get_boolean_member ("verified");
      this.protected   = user.get_boolean_member ("protected");
      if (!status.get_null_member ("in_reply_to_status_id"))
        this.reply_id  = status.get_int_member ("in_reply_to_status_id");
    }

    if (status.has_member ("quoted_status")) {
      var quoted_status = status.get_object_member ("quoted_status");
      this.quoted_tweet = parse_mini_tweet (quoted_status);
      parse_entities (this.quoted_tweet, quoted_status);
    } else if (this.retweeted_tweet != null &&
               status.get_object_member ("retweeted_status").has_member ("quoted_status")) {
      var quoted_status = status.get_object_member ("retweeted_status").get_object_member ("quoted_status");
      this.quoted_tweet = parse_mini_tweet (quoted_status);
      parse_entities (this.quoted_tweet, quoted_status);
    }


    if (status.has_member ("current_user_retweet")) {
      this.my_retweet = status.get_object_member ("current_user_retweet").get_int_member ("id");
      this.retweeted  = true;
    }

    this.avatar = Twitter.get ().get_avatar (avatar_url, (a) => {
      this.avatar = a;
    });

#if DEBUG
    var gen = new Json.Generator ();
    gen.root = status_node;
    gen.pretty = true;
    this.json_data = gen.to_data (null);
#endif
  }

  /**
   * Returns the text of this tweet in pango markup form,
   * i.e. formatted with the html tags used by pango.
   *
   * @return The tweet's formatted text.
   */
  public string get_formatted_text () {
    MiniTweet t;
    if (this.retweeted_tweet != null)
      t = this.retweeted_tweet;
    else
      t = this.source_tweet;

    return TextTransform.transform_tweet (t, 0);
  }

  /**
   * Returns the text of this tweet, with its long urls.
   * Twitter automatically shortens them.
   *
   * @return The tweet's text with long urls
   */
  public string get_real_text () {
    MiniTweet t;
    if (this.retweeted_tweet != null)
      t = this.retweeted_tweet;
    else
      t = this.source_tweet;

    return TextTransform.transform_tweet (t,
                                          TransformFlags.EXPAND_LINKS);
  }

  public string get_trimmed_text () {
    MiniTweet t;
    if (this.retweeted_tweet != null)
      t = this.retweeted_tweet;
    else
      t = this.source_tweet;

    int64 quote_id = this.quoted_tweet != null ? this.quoted_tweet.id : -1;

    return TextTransform.transform_tweet (t,
                                          Settings.get_text_transform_flags (),
                                          quote_id);
  }

}
