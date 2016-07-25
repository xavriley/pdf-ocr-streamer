require 'sinatra'
require "sinatra/streaming"
require 'rest-client'
require 'pathname'
require 'open-uri'
require 'zipruby'
require 'mimemagic'
require 'json'

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
      <label for="url">Enter the URL of a PDF</lable>
			<input type="text" id="url" name="url" />
      <p>OR:</p>
      <label for="company">Enter a UK company number</label>
      <input type="text" id="company" name="company" />
      <input type="submit" />
    </form>
  </body>
  </html>
  HTML
end

post '/upload' do
  if not params[:company].to_s.empty?
    filings_res = RestClient.get("https://#{ENV['COMPANIES_HOUSE_TOKEN']}@api.companieshouse.gov.uk/company/#{params[:company]}/filing-history?items_per_page=100&category=annual-return,accounts")

		case filings_res.code
		when 0, 200 # zero means cached
			if !filings_res.body.empty?
				filings_list = JSON.parse(filings_res.body)["items"]
			else
				return nil
			end
		else
      status 503
			body "Couldn't retrieve fillings from Companies House API"
		end

    ch_filing = filings_list.select {|x| x["type"] == "AA" }.sort_by {|x|
			Date.parse((x["date"] || x["action_date"]))
		}.last

		doc_meta_url = ch_filing.fetch("links", {}).fetch("document_metadata", nil)
    doc_meta = JSON.parse(RestClient::Request.execute(method: :get,
                                                      url: doc_meta_url,
                                                      verify_ssl: false,
                                                      user: ENV['COMPANIES_HOUSE_TOKEN']
                                                     ).body)

		doc_mime_type = doc_meta["resources"].sort_by {|k,v|
			case k
			when /html/
				1
			when /pdf/
				2
			else
				3
			end
		}.first.first # yuck!

		doc_content_url = doc_meta.fetch("links", {}).fetch("document", nil)

    aws_params = {"Accept" => doc_mime_type}
    doc_s3_content_res = RestClient::Request.execute(method: :get,
                                                     url: doc_content_url,
                                                     verify_ssl: false,
                                                     user: ENV['COMPANIES_HOUSE_TOKEN'],
                                                     max_redirects: 0,
                                                     headers: aws_params) {|response,request,result,&block|
                                                       # called in block because 302 response with no redirect
                                                       # raises error otherwise
                                                       @doc_s3_content_url = response.headers[:location]
                                                     }

    params[:url] = @doc_s3_content_url
  end

  stream do |out|
    # evade Heroku timeout
    out.puts "<!-- #{params[:url]} -->\n"
    out.puts "<pre>"
    out.flush

    url = params[:url]

    # We create a local representation of the remote resource
    local_resource = local_resource_from_url(url)

    # We have a copy of the remote file for processing
    local_copy_of_remote_file = local_resource.file

    # Do your processing with the local file
    reopened_file = File.open(local_copy_of_remote_file.path, 'rb')
    reopened_mime = MimeMagic.by_magic(reopened_file).type
    reopened_file.rewind

    if reopened_mime.include? "pdf"
      zipbytes = RestClient.put "https://dockertikatest.herokuapp.com/unpack/all", reopened_file.read, :content_type => reopened_mime
      images = []
      Zip::Archive.open_buffer(zipbytes) do |zf|

        zf.each {|f|
          mimetype = MimeMagic.by_path(f.name)
          if mimetype and mimetype.image?
            images << {name: f.name, file: f.read, mimetype: mimetype}
          end
        }
      end

      images.sort_by {|i| i[:name].gsub(/(\d+)/) {|n| sprintf("%05d", n.to_i) } }.each do |i|
        out.puts RestClient.put("https://dockertikatest.herokuapp.com/tika", i[:file], :content_type => i[:mimetype])
        out.flush
      end
    else
      out.puts RestClient.put("https://dockertikatest.herokuapp.com/tika", reopened_file.read, :content_type => reopened_mime)
    end

    reopened_file.close

    out.puts "</pre>"
  end
end
