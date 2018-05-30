require 'sinatra'
require 'line/bot'

require 'open-uri'
require 'nokogiri'

require 'ghee'

def client
  @client ||= Line::Bot::Client.new { |config|
    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

def gh
  Ghee.basic_auth(ENV['GIT_ACT'], ENV['GIT_PWD'])
end

def get_tour(lim)
  p gh
  tused = gh.gists(ENV["HASH_GIST_ID"])['files']['hash.txt']['content'].split(/\s/) rescue []

  doc = Nokogiri::HTML(open("https://statsroyale.com/tournaments"))

  frac = doc.xpath('//div[starts-with(@class, "challenges__row")]').map do |el|
    u = el.children[0].text.split
    u.empty? || u[0][0] == ?# ? nil : u[0]
  end.compact

  seri = doc.xpath('//div[starts-with(@class, "challenges__row")]').map do |el|
    u = el.children[0].text.split
    u.empty? || u[0][0] != ?# ? nil : u[0]
  end.compact

  name = doc.xpath('//a[starts-with(@class, "ui__blueLink")]').map do |el|
    el.children[0].text
  end

  s = frac.zip(name.zip(seri)).map(&:flatten).map do |t|
    f, n, x = t
    a, b = f.split(?/).map &:to_i
    if a < b && b >= lim && !(tused.include?(x))
      tused << x if b > 50
      f + ?: + n + ?: + ?\n + "clashroyale://joinTournament?id=#{x[1...x.size]}" + ?\n
    end
  end.compact.join(?\n)

  tused.shift while tused.size > 20
  gh.gists(ENV['HASH_GIST_ID']).patch({files: {'hash.txt': {content: tused.join(?\n)}}})

  return 'No tournament found' if s.empty?
  s
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    t = get_tour(100)
    if t != 'No tournament found'
      uids = gh.gists(ENV["LNID_GIST_ID"])['files']['lnid.txt']['content'].split(/\s/)
      uids.each do |uid|
        message = {
          type: 'text',
          text: t
        }
        client.push_message(uid, message)
      end
    end
  else
    events = client.parse_events_from(body)
    events.each { |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          message = {
            type: 'text',
            text: get_tour(50)
          }
          uid = event['source']['userId']
          uids = gh.gists(ENV["LNID_GIST_ID"])['files']['lnid.txt']['content'].split(/\s/)
          uids << uid
          uids.uniq!
          gh.gists(ENV["LNID_GIST_ID"]).patch({files: {'lnid.txt': {content: uids.join(?\n)}}})
          client.reply_message(event['replyToken'], message)
        when Line::Bot::Event::MessageType::Image, Line::Bot::Event::MessageType::Video
          response = client.get_message_content(event.message['id'])
          tf = Tempfile.open("content")
          tf.write(response.body)
        end
      else
      end
    }

    "OK"
  end

end
