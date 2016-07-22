require 'pmap'
require 'sinatra'
require "sinatra/streaming"
require 'rest-client'
require 'pathname'
require 'open-uri'
require 'zipruby'
require 'mimemagic'

class LocalResource
	attr_reader :uri

	def initialize(uri)
		@uri = uri
	end

	def file
		@file ||= Tempfile.new(tmp_filename, tmp_folder, encoding: encoding).tap do |f|
			io.rewind
			f.write(io.read)
			f.close
		end
	end

	def io
		@io ||= uri.open
	end

	def encoding
		io.rewind
		io.read.encoding
	end

	def tmp_filename
		[
      Pathname.new(uri.path).basename.to_s,
      Pathname.new(uri.path).extname.to_s
		]
	end

	def tmp_folder
    "/tmp"
	end
end

def local_resource_from_url(url)
	LocalResource.new(URI.parse(url))
end

get '/' do
  <<-HTML
  <html>
  <head><title>Controlling party</title></head>
  <body>
    <form action="/upload" method="post" enctype="multipart/form-data">
			<input type="text" name="url" />
      <input type="submit" />
    </form>
  </body>
  </html>
  HTML
end

post '/upload' do
  stream do |out|
    # evade Heroku timeout
    out.puts ""
    out.flush

    url = params[:url]

    # We create a local representation of the remote resource
    local_resource = local_resource_from_url(url)

    # We have a copy of the remote file for processing
    local_copy_of_remote_file = local_resource.file

    # Do your processing with the local file
    zipbytes = RestClient.put "https://dockertikatest.herokuapp.com/unpack/all", File.open(local_copy_of_remote_file.path, 'rb').read, :content_type => 'application/pdf'

    images = []
    Zip::Archive.open_buffer(zipbytes) do |zf|

      zf.each {|f|
        if f.name.include? 'image'
          mimetype = MimeMagic.by_path(f.name).type
          images << {file: f.read, mimetype: mimetype}
        end
      }
    end

    images.each do |i|
      out.puts RestClient.put("https://dockertikatest.herokuapp.com/tika", i[:file], :content_type => i[:mimetype])
      out.flush
    end
  end
end
