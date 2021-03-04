class Api::V1::OmiaiLikeController < ApplicationController
  # callbackアクションのCSRFトークン認証を無効
  protect_from_forgery :except => [:callback]
  # 足跡ツールline_botのクライアント
  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_id = ENV["LINE_OMIAI_SUGGEST_ID"]
      config.channel_secret = ENV['LINE_OMIAI_SUGGEST_SECRET']
      config.channel_token = ENV['LINE_OMIAI_SUGGEST_TOKEN']
    }
  end

  def push(text)
    message = {
      type: 'text',
      text: text
    }
    user_id = "U1193124d73215ce741b9c08b80f84ef5"
    client.push_message(user_id, message)
    user_id2 = "U3412fa03c2c730c1512cdffea0eb4be7"
    client.push_message(user_id2, message)
  end

  def push_image(url, result, sim, file_name)
    if result['hometown_area'] == "JP-13"
      @area = "東京"
    elsif result['hometown_area'] == "JP-11"
      @area = "埼玉"
    else
      @area = "その他"
    end
    like_data = { method: "like", user_id: result["user_id"].to_s, user_name: result['nickname'], file_name: file_name }.to_json
    delete_data = { method: "delete", user_id: result["user_id"].to_s, user_name: result['nickname'], file_name: file_name }.to_json
    message = {
      "type": "template",
      "altText": "This is a buttons template",
      "template": {
        "type": "buttons",
        "thumbnailImageUrl": url,
        "imageAspectRatio": "rectangle",
        "imageSize": "cover",
        "imageBackgroundColor": "#FFFFFF",
        "title": result['nickname'],
        "text": result['age'].to_s + "歳 / " + @area + " / " + sim + "%マッチ",
        "defaultAction": {
          "type": "uri",
          "label": "View detail",
          "uri": url
        },
        "actions": [
          {
            "type": "postback",
            "label": "いいね！",
            "data": like_data
          },
          {
            "type": "postback",
            "label": "画像削除",
            "data": delete_data
          },
          {
            "type": "uri",
            "label": "詳細（未実装）",
            "uri": url
          }
        ]
      }
    }
    user_id = "U1193124d73215ce741b9c08b80f84ef5"
    client.push_message(user_id, message)
    user_id2 = "U3412fa03c2c730c1512cdffea0eb4be7"
    client.push_message(user_id2, message)
  end

  def callback
    @body = request.body.read
    @signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(@body, @signature)
      error 400 do
        'Bad Request'
      end
    end
    events = client.parse_events_from(@body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          if event['message']['text'] == "起動"
            push("「起動」が押された！")
            index
          end
          if event['message']['text'].include?("-")
            token = OmiaiToken.find_or_initialize_by(id: 1)
            if token.token == event['message']['text']
              push("既に同じアクセストークンが保存されています")
            else
              token.update(token: event['message']['text'])
              push("アクセストークンを保存しました！")
            end
          end
        end
      when Line::Bot::Event::Postback
        if event['postback']['data']
          object = JSON.load(event['postback']['data'])
          if object['method'] == "like"
            omiai_like(object['user_id'])
            push object['user_name'] + "さんをlikeしました！"
          elsif object['method'] == "delete"
            object_delete(object['file_name'])
            push object['user_name'] + "さんの画像をS3から削除しました"
          else
            push "何した？"
          end
        end
      end
    end
  end

  def index
    begin
      push("いい人探してきますね！！")
      i = 0
      loop do
        begin
          token = OmiaiToken.find(1)
          res = get_results(token)
          res_body = JSON.parse(res.body)
          if res_body['results']
            res_body['results'].each do |result|
              user_id = result['user_id']
              if OmiaiLikedUser.exists?(user_id: user_id)
                p result['nickname'] + "さんは既に画像判定をしたユーザです。スルーします。"
              else
                OmiaiLikedUser.create(user_id: user_id)
                str = result['photograph_list'][0]['path']
                image_url = str.gsub(/\u003d/, "=").gsub(/\u0026/, "&")
                p image_url
                file_name = get_image(image_url, result['user_id'])
                object_uploaded(file_name)
                similar = compare_images(file_name, "target1.jpg")
                if similar > 15
                  similar_i = similar.to_i
                  similar_s = similar_i.to_s
                  s3_url = get_object_url(file_name)
                  push_image(s3_url, result, similar_s, file_name)
                  p result['nickname'] + "さんの情報をLINEに送信しました"
                else
                  p result['nickname'] + "さんは似ていません。スルーします。"
                  object_delete(file_name)
                end
              end
            end
            # 成功したため、iを初期化する
            i = 0
          else
            if i < 10
              p "再検索します"
              p (i + 1).to_s + "回目の再検索です"
              i += 1
              sleep rand(20..30)
            else
              raise
            end
          end
        rescue
          # 6回連続で失敗した場合は終了
          if i < 10
            i += 1
            p (i + 1).to_s + "回目の処理失敗です"
            retry
          else
            p i.to_s + "回処理が失敗しました。プログラムを終了します。"
            push(i.to_s + "回処理が失敗しました。プログラムを終了します。")
            raise
          end
        end
      end
    rescue
      p "====処理が中断されました===="
      push("現在処理が止まってるよ！アクセストークンの有効期限が終わったのかも！")
      return false
    end
  end

  def omiai_like(user_id)
    token = OmiaiToken.find(1)
    data = { action: "like", omi_access_token: token.token, to_user_id: user_id, use_point: 0 }
    html_post("https://api2.omiai-jp.com/interest/deliver", "101", data)
  end
end
