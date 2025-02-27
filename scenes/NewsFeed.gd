extends RichTextLabel

const news_item = """
[url={link}]{title}[/url]

{author} - {date}

{contents}

[url={link}]{link}[/url]

======
"""

var images: Dictionary
var local_images : Dictionary

signal images_downloaded()

func _ready():
	#connect("images_downloaded", self, "_on_images_downloaded")
	_refresh_news()

# Updates display of news
func _refresh_news():
	$req.request("https://godotengine.org/news")
	var response = yield($req,"request_completed")
	_update_news_feed(_get_news(response[3]))

# Generates text bases on an array of dictionaries containing strings to 
# interpolate
func _update_news_feed(feed : Array):
	bbcode_text = "[center] === GODOTENGINE.ORG/NEWS ===[/center]\n\n"
	for item in feed:
		bbcode_text += news_item.format(item)
	# parsing jpg buffer data currently not working.
	# see https://github.com/godotengine/godot/issues/45523
	#_download_images()

func _on_images_downloaded():
	bbcode_text = bbcode_text.format(local_images)

# Analyzes html for <div class="news-item"> elements
# which will be further parsed by _parse_news_item()
func _get_news(buffer) -> Array:
	var parsed_news = []

	var xml = XMLParser.new()
	var error = xml.open_buffer(buffer)

	if error == OK:
		while(true):
			var err = xml.read()

			if err != OK:
				if err != ERR_FILE_EOF:
					print("Error %s reading XML" % err)
				break

			# Look for <div class="news-item"> elements
			if xml.get_node_type() == XMLParser.NODE_ELEMENT and xml.get_node_name() == "div":
				var class_attr = xml.get_named_attribute_value_safe("class")
				# Take note of the offsets from <div class="news-item> to </div>
				# to further analyze
				if "news-item" in class_attr:
					var tag_open_offset = xml.get_node_offset()
					xml.skip_section()
					xml.read()
					var tag_close_offset = xml.get_node_offset()
					parsed_news.append(_parse_news_item(buffer, tag_open_offset, tag_close_offset))
					
	else:
		print("Error %s getting download info" % error)
	return parsed_news

# Extract the necesary info for each news item
func _parse_news_item(buffer, begin_ofs, end_ofs):
	
	var parsed_item = {}
	var xml = XMLParser.new()
	var error = xml.open_buffer(buffer)
	xml.seek(begin_ofs) # automatically does xml.read()
	
	# We iterate over every node in the range specified by
	# begin_ofs and end_ofs fetching the info we care about
	# strip_edges is needed since text nodes seem to contain
	# every character as it is in the html, including
	# tabulation and leading spaces
	while(xml.get_node_offset() != end_ofs):
		if xml.get_node_type() == XMLParser.NODE_ELEMENT:
			match xml.get_node_name():
				"div":
					if "image" in xml.get_named_attribute_value_safe("class"):
						var image_style = xml.get_named_attribute_value_safe("style")
						var url_start = image_style.find("'") + 1
						var url_end = image_style.find_last("'")
						var image_url = image_style.substr(url_start,url_end - url_start)
						
						# Images will be downloaded and their bbcode will be 
						# interpolated in a second pass so for now we store them 
						# as "{image#<hash of url>}"
						var image_code = "image#%s" % image_url.hash()
						parsed_item["image"] = "{%s}" % image_code
						images[image_code] = image_url
						parsed_item["link"] = xml.get_named_attribute_value_safe("href")
				"h3":
					if "title" in xml.get_named_attribute_value_safe("class"):
						xml.read()
						parsed_item["title"] = xml.get_node_data().strip_edges().to_upper() if xml.get_node_type() == XMLParser.NODE_TEXT else ""
				"h4":
					if "author" in xml.get_named_attribute_value_safe("class"):
						xml.read()
						parsed_item["author"] = xml.get_node_data().strip_edges() if xml.get_node_type() == XMLParser.NODE_TEXT else ""
				"span":
					if "date" in xml.get_named_attribute_value_safe("class"):
						xml.read()
						parsed_item["date"] = xml.get_node_data().strip_edges() if xml.get_node_type() == XMLParser.NODE_TEXT else ""
				"p":
					xml.read()
					parsed_item["contents"] = xml.get_node_data().strip_edges() if xml.get_node_type() == XMLParser.NODE_TEXT else ""
		xml.read()
		
	# Return the dictionary with the news entry once we are done
	return parsed_item

# Downloads all image  thumbnails for news snippets
func _download_images():
	var dir = Directory.new()
	dir.make_dir("user://images/")
	var searches = 0
	for img_id in images.keys():
		while searches > 4: #four connections max
			yield(get_tree().create_timer(0.1),"timeout")
		searches += 1
		var req = HTTPRequest.new()
		add_child(req)
		
		var local_path = "user://images/" + img_id
		local_images[img_id] = "[img=50]%s%s[/img]" % [ local_path, ".tex" ]
		req.request(images[img_id])
		var response = yield(req,"request_completed")
		if response[1] == 200:
			_save_texture(response[3], local_path)
		searches -= 1
		req.queue_free()
	emit_signal("images_downloaded")

func _save_texture(buffer : PoolByteArray, path: String):
	var image = Image.new()
	var error = image.load_jpg_from_buffer(buffer)
	if error != OK:
		print("Error %s loading jpg from buffer" % error)
		return
	else:
		var texture = ImageTexture.new()
		texture.create_from_image(image)
		ResourceSaver.save(path + "tex",texture)

# Handle clicking on links
func _on_NewsFeed_meta_clicked(meta):
	print(str(meta))
	OS.shell_open(str(meta))

