local feed = {
  {
    id = "ANN_180226_1",
	icon = 1,
	title = "News 10-02",
	from = "ShaDis",
	body = "Hey there, welcome to my HP! As you can see, we have a brand new e-mail announcement system :D\nI promise to try not to completely fill your inbox with announcements and stuff."..
    "In any case, check out the updates to my HP\n-Added Jukebox to decor shop\n- Added music shop where you can buy songs\nWith this update, you'll be able to place a Jukebox as a decoration"..
	" and use it to change the song that plays for people who fisit your HP. I hope you enjoy! Special thanks to ragashii and D3str0y3d for the help!\n-ShaDis",
	mug_texture_path = "/server/assets/ezlibs-assets/eznpcs/mug/luigi-idle.png",
	mug_animation_path = "/server/assets/ezlibs-assets/eznpcs/mug/mug.animation",
	notify_message = "Looks like you got a new e-mail",
  },

  -- Add more announcements here. New ones MUST use new unique ids.
}

feed.tombstones = {
  -- Put email IDs you want deleted server-wide here:
--  "ANN_180226_1",

}

return feed