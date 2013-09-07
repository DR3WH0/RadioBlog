require 'selenium-webdriver'
require 'yaml'
require 'open-uri'
require 'xmlsimple'
require 'erb'
require 'googl'

include ERB::Util

def get_radio # station name
	print "Enter artist or tag: "
	station = gets.chomp
	puts "\nLoading \'#{station}\' Radio in Firefox >> Please wait..."
	station
end

def load_radio(station) # in Firefox 'lastfm' profile
	begin
		driver = Selenium::WebDriver.for :firefox, :profile => 'lastfm'
		driver.manage.window.resize_to(580, 615)
		driver.navigate.to "http://last.fm/listen/"
		element = driver.find_element(:name, "name")
		element.send_keys "#{station}"
		element.submit
		driver
	rescue Selenium::WebDriver::Error::NoSuchElementError
		puts "ERROR >> load Last.fm >> Please try again."
		exit
	end
end

def shorten(url, blog) # create short urls with goo.gl
	begin
		urlshortener = Googl.shorten(url)
		shorturl = urlshortener.short_url
		shorturl
	rescue Exception
		puts "ERROR >> create goo.gl URL"
		"#{blog}"
	end
end

def format_hash(tagdata)
	tagname = String.new
	hashtag = String.new
	tagname = tagdata['name'][0]
	hashtag = tagname.gsub(/([- ])/, '').downcase
	hashtag.gsub!("\:", '')
	hashtag
end

def get_tags(tags_url, tweetlen) # get up to three tags
	begin
		hashtags = String.new
		open(tags_url, :read_timeout=>5) do |body|
			data = XmlSimple.xml_in body.read

			toptags = data['toptags'][0]
			unless toptags['tag'] == nil # some tracks have no tags
				tagone = toptags['tag'][0]
				tagtwo = toptags['tag'][1]
				tagtre = toptags['tag'][2]
				onehash = format_hash(tagone)
				tweetlen = tweetlen + html_escape(onehash).length + 2
				unless tweetlen > 140 # cascading tweet length & nil check
					unless tagtwo == nil
						twohash = format_hash(tagtwo)
						tweetlen = tweetlen + html_escape(twohash).length + 2
						unless tweetlen > 140
							unless tagtre == nil
								trehash = format_hash(tagtre)
								tweetlen = tweetlen + html_escape(trehash).length + 2
								unless tweetlen > 140
									hashtags = "#lastfm #music ##{onehash} ##{twohash} ##{trehash}"
								else
									puts "ERROR >> tweet too long (#{tweetlen}): ##{trehash} deleted (T3)"
									hashtags = "#lastfm #music ##{onehash} ##{twohash}"
								end
							else
								hashtags = "#lastfm #music ##{onehash} ##{twohash}" # T3 nil
							end
						else
							puts "ERROR >> tweet too long (#{tweetlen}): ##{twohash} deleted (T2)"
							hashtags = "#lastfm #music ##{onehash}"
						end
					else
						hashtags = "#lastfm #music ##{onehash}" # T2 nil
					end
				else
					puts "ERROR >> tweet too long (#{tweetlen}): ##{onehash} deleted (T1)"
					hashtags = "#lastfm #music"
				end
			else
				hashtags = "#lastfm #music" # T1 nil
			end
		end

		hashtags

	rescue OpenURI::HTTPError # 400 Bad Request
		puts "ERROR >> track tags (400)"
		"#lastfm #music"
	rescue Timeout::Error # connection timed out
		puts "ERROR >> track tags (timeout)"
		"#lastfm #music"
	end
end

def free_download(info_url, artist, name, hashtags, tweet, tcolen, blog)
	begin
		open(info_url, :read_timeout=>5) do |body|
			data = XmlSimple.xml_in body.read

			track = data['track'][0]
			unless track['freedownload'] == nil
				puts "FREE MP3  \'#{artist} - #{name}.mp3\'"
				yamlname = "#{artist} - #{name}"
				filename = "\'#{artist} - #{name}.mp3\'"
				dl_url = track['freedownload'][0]
				shortdlurl = shorten(dl_url, blog)

				dl_text = html_escape("FREE #MP3 #{filename} #{shortdlurl} #{hashtags}")
				dl_check = html_escape("FREE #MP3 #{filename}  #{hashtags}")
				dl_textlen = dl_check.length + tcolen

				if dl_textlen > 140 # tweet length check
					puts "ERROR >> tweet too long (#{dl_textlen}): track tags deleted"
					dl_text = html_escape("FREE #MP3 #{filename} #{shortdlurl} #lastfm #music")
					dl_check = html_escape("FREE #MP3 #{filename}  #lastfm #music")
					dl_textlen = dl_check.length + tcolen
					if dl_textlen > 140
						puts "ERROR >> tweet still too long (#{dl_textlen}): #music tag deleted"
						dl_text = html_escape("FREE #MP3 #{filename} #{shortdlurl} #lastfm")
						dl_check = html_escape("FREE #MP3 #{filename}  #lastfm")
						dl_textlen = dl_check.length + tcolen
						if dl_textlen > 140
							puts "ERROR >> file name is huge (#{dl_textlen}): #lastfm tag deleted"
							dl_text = html_escape("FREE #MP3 #{filename} #{shortdlurl}")
						end
					end
				end

				free_dl = %x[twurl -d "status=#{dl_text}" "#{tweet}"]

				config = YAML::load(File.open('_config.yml'))
				tracks = config['tracks']
				names = Array.new

				tracks.each do |track|
					names.push(track['name'])
				end

				unless names.include? yamlname
					# add track to YAML formatted log file
					time = Time.new
					t = time.strftime("%Y-%m-%d %a %H:%M:%S")
					log = "  - name : #{artist} - #{name}\n    url : #{shortdlurl}\n    date: #{t}\n"
					File.open('_config.yml', 'a') { |file| file.write(log) }
					shortdlurl
				end
			end
		end

	rescue OpenURI::HTTPError # 400 Bad Request
		puts "ERROR >> free download info (400)"
	rescue Timeout::Error # connection timed out
		puts "ERROR >> free download info (timeout)"
	end
end

def get_album(info_url)
	begin
		open(info_url, :read_timeout=>5) do |body|
			data = XmlSimple.xml_in body.read

			track = data['track'][0]
			unless track['album'] == nil
				album = track['album'][0]
				title = album['title'][0]
				image = album['image'][2]['content']
				"![Album Cover](#{image} \"#{title}\")"
			else
				"![DR3WH0 Logo](https://dl.dropboxusercontent.com/u/8239797/DR3WH0.png \"DR3WH0 RadioBlog\")"
			end
		end

	rescue OpenURI::HTTPError # 400 Bad Request
		puts "ERROR >> get image (400)"
		"![DR3WH0 Logo](https://dl.dropboxusercontent.com/u/8239797/DR3WH0.png \"DR3WH0 RadioBlog\")"
	rescue Timeout::Error # connection timed out
		puts "ERROR >> get image (timeout)"
		"![DR3WH0 Logo](https://dl.dropboxusercontent.com/u/8239797/DR3WH0.png \"DR3WH0 RadioBlog\")"
	end
end

def manage_radio(driver, station, q) # resume radio & tweet tracks
	blog = "http://goo.gl/l8vrty"
	infotags = "#lastfm #ruby #webdriver #twurl"
	tweet = "/1.1/statuses/update.json"
	config = YAML::load(File.open('_config.yml'))
	lfm_user = config['lastfm']['username']
	lfm_key = config['lastfm']['api']
	lfm_url = "http://ws.audioscrobbler.com/2.0/?method="
	recent_url = "#{lfm_url}user.getrecenttracks&user=#{lfm_user}&api_key=#{lfm_key}&limit=1"
	tcolen = 22 # t.co short_url_length https://dev.twitter.com/docs/api/1.1/get/help/configuration
	@names = Array.new
	num = 0

	puts "Last.fm loaded >> AutoPlay ON"
	puts "\nEnter \'quit\' at any time..."
	radiobegin = %x[twurl -d "status=BEGIN #{station} radio #{infotags} #{blog}" "#{tweet}"]

	time = Time.new
	t = time.strftime("%Y-%m-%d")
	dt = time.strftime("%A, %B %e, %Y")
	filestation = station.gsub(' ', '-')
	unless File.file?("./_posts/#{t}-#{filestation}-radio.md")
		post = "---\nlayout: post\npublished: true\ncategory: radio\n---\n\n**#{dt}**\n\n"
	else
		post = "\n\n**#{dt}**\n\n"
	end
	File.open("./_posts/#{t}-#{filestation}-radio.md", 'a') { |file| file.write(post) }

	loop do
		sleep(60) # poll lfm api every 60 seconds
		break if q[:user_quit]

		# close 'are you listening' dialog
		elements = Array.new
		elements = driver.find_elements(:class, "dialogConfirm")
		if elements.size > 0
			element = driver.find_element(:class, "dialogConfirm")
			element.submit
			puts "AUTOPLAY  #{station} radio"
			radioresume = %x[twurl -d "status=AUTOPLAY #{station} radio #{infotags} #{blog}" "#{tweet}"]
		end
		
		begin # get most recent track
			open(recent_url, :read_timeout=>5) do |body|
			data = XmlSimple.xml_in body.read

				recenttracks = data['recenttracks'][0]
				if recenttracks['track'][1] == nil
					track = recenttracks['track'][0]
				else  # ignore 'listening now' tracks
					track = recenttracks['track'][1]
				end

				@artist = track['artist'][0]['content']
				@apiartist = @artist.dup
				@artist.gsub!("&", "a.")
				@artist.gsub!("\"", "\'")

				@name = track['name'][0]
				@apiname = @name.dup
				@name.gsub!("&", "a.")
				@name.gsub!("\"", "\'")

				url = track['url'][0]
				@shorturl = shorten(url, blog)
			end

		rescue OpenURI::HTTPError # 400 Bad Request
			puts "ERROR >> recent tracks (400)"
			next
		rescue Timeout::Error # connection timed out
			puts "ERROR >> recent tracks (timeout)"
			next
		end

		unless @names.include? @name # tweet new track
			urlartist = url_encode("#{@apiartist}")
			urltrack = url_encode("#{@apiname}")
			tags_url = "#{lfm_url}track.gettoptags&api_key=#{lfm_key}&artist=#{urlartist}&track=#{urltrack}"
			info_url = "#{lfm_url}track.getInfo&api_key=#{lfm_key}&artist=#{urlartist}&track=#{urltrack}"

			sleep(2) # give the lfm api a break
			tweetbase = html_escape("00:00:00  #{@name} by #{@artist}  #lastfm #music")
			tweetlen = tweetbase.length + tcolen
			@hashtags = get_tags(tags_url, tweetlen)

			time = Time.new
			displaytime = time.strftime("%H:%M:%S")
			displaytext = "#{displaytime}  #{@name} by #{@artist}"

			text = html_escape("#{displaytime}  #{@name} by #{@artist} #{@shorturl} #{@hashtags}")
			text_check = html_escape("#{displaytime}  #{@name} by #{@artist}  #{@hashtags}")
			textlen = text_check.length + tcolen
			@names.push(@name) # add track to session array

			if textlen > 140 # double check tweet length
				if @hashtags.length > 14
					puts "ERROR >> tweet too long (#{textlen}): track tags deleted"
					text = html_escape("#{displaytime}  #{@name} by #{@artist} #{@shorturl} #lastfm #music")
					text_check = html_escape("#{displaytime}  #{@name} by #{@artist}  #lastfm #music")
					textlen = text_check.length + tcolen
					if textlen > 140
						puts "ERROR >> tweet still too long (#{textlen}): #music tag deleted"
						text = html_escape("#{displaytime}  #{@name} by #{@artist} #{@shorturl} #lastfm")
						text_check = html_escape("#{displaytime}  #{@name} by #{@artist}  #lastfm")
						textlen = text_check.length + tcolen
						if textlen > 140
							puts "ERROR >> tweet still too long (#{textlen}): #lastfm tag deleted"
							text = html_escape("#{displaytime}  #{@name} by #{@artist} #{@shorturl}")
							text_check = html_escape("#{displaytime}  #{@name} by #{@artist} ")
							textlen = text_check.length + tcolen
							if textlen > 140
								puts "ERROR >> track name is huge: url deleted"
								text = html_escape("#{displaytime}  #{@name} by #{@artist} #lastfm")
							end
						end
					end
				else
					puts "ERROR >> tweet too long (#{textlen}): #music tag deleted"
					text = html_escape("#{displaytime}  #{@name} by #{@artist} #{@shorturl} #lastfm")
					text_check = html_escape("#{displaytime}  #{@name} by #{@artist}  #lastfm")
					textlen = text_check.length + tcolen
					if textlen > 140
						puts "ERROR >> tweet still too long (#{textlen}): #lastfm tag deleted"
						text = html_escape("#{displaytime}  #{@name} by #{@artist} #{@shorturl}")
						text_check = html_escape("#{displaytime}  #{@name} by #{@artist} ")
						textlen = text_check.length + tcolen
						if textlen > 140
							puts "ERROR >> track name is huge: url deleted"
							text = html_escape("#{displaytime}  #{@name} by #{@artist} #lastfm")
						end
					end
				end
			end

			unless @names.size == 1 # ignore first stale track pulled from api
				tracktweet = %x[twurl -d "status=#{text}" "#{tweet}"]
				puts "#{displaytext} (#{textlen})"
				num += 1

				urlartist = @artist.gsub(' ', '+')
				artisturl = "http://www.last.fm/music/#{urlartist}"

				sleep(2) # give the lfm api a break
				shortdlurl = free_download(info_url, @artist, @name, @hashtags, tweet, tcolen, blog)
				sleep(2) # give the lfm api a break
				album = get_album(info_url)

				if shortdlurl
					post = "*   #{displaytime}  [#{@name}](#{@shorturl}) by [#{@artist}](#{artisturl}) [FREE MP3](#{shortdlurl})\n\n    #{album}\n\n"
				else
					post = "*   #{displaytime}  [#{@name}](#{@shorturl}) by [#{@artist}](#{artisturl})\n\n    #{album}\n\n"
				end
				File.open("./_posts/#{t}-#{filestation}-radio.md", 'a') { |file| file.write(post) }
			end
		end
	end

	if num == 1 then t = "track" else t = "tracks" end	
	radioend = %x[twurl -d "status=END #{station} radio (#{num} #{t}) #{infotags} #{blog}" "#{tweet}"]
	puts "Last.fm \'#{station}\' Radio (#{num} #{t}) >> Goodbye!"
	driver.quit
	exit
end

station = get_radio
driver = load_radio(station)

q = Thread.new do # end radio station on 'quit'
	until gets.chomp == 'quit' ; end
	Thread.current[:user_quit] = true
end

manage_radio(driver, station, q)
