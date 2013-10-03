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

using Gtk;

[GtkTemplate (ui = "/org/baedert/corebird/ui/dm-list-entry.ui")]
class DMListEntry : Gtk.ListBoxRow {
  [GtkChild]
  private Gtk.Image avatar_image;
  [GtkChild]
  private Gtk.Label text_label;
  [GtkChild]
  private Gtk.Label screen_name_label;
  [GtkChild]
  private Gtk.Label name_label;

  public string text {
    set { text_label.label = value; }
  }
  public string screen_name {
    set { screen_name_label.label = "@" + value; }
  }
  public new string name {
    set { name_label.label = value; }
  }

  public int64 id;

  public DMListEntry () {

  }
}

