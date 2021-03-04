class ApplicationController < ActionController::Base
  require 'line/bot'
  require 'open-uri'
  require "aws-sdk"
  require 'aws-sdk-s3'
  require 'net/https'

  # 画像をローカルに保存する
  def get_image(url, prefix)
    prefix_str = prefix.to_s
    file = '/myapp/images/' + prefix_str + '.jpg'
    # 取得した画像URLから画像をダウンロードする
    File.open(file, 'w+b') do |pass|
      OpenURI.open_uri(url) do |recieve|
        pass.write(recieve.read)
      end
    end
    prefix_str + '.jpg'
  end

  # Rekognitionで画像の比較
  def compare_images(src_keyname, target_keyname)
    rekog = Aws::Rekognition::Client.new(region: "ap-northeast-1", access_key_id: ENV['ACCESS_KEY_ID'],
                                         secret_access_key: ENV['SECRET_ACCESS_KEY'])
    begin
      response = rekog.compare_faces({
                                       source_image: { 's3_object': {
                                         bucket: ENV['S3_BUCKETS_NAME'],
                                         name: src_keyname,
                                       } },
                                       target_image: { 's3_object': {
                                         bucket: ENV['S3_BUCKETS_NAME'],
                                         name: target_keyname,
                                       } },
                                       similarity_threshold: 1.0
                                     })
      response['face_matches'][0]['similarity']
    rescue
      0
    end
  end

  # S3にuploadしローカルに一時的に保存した画像を削除する
  def object_uploaded(file_name)
    s3resoruce = Aws::S3::Resource.new(
      access_key_id: ENV['ACCESS_KEY_ID'],
      secret_access_key: ENV['SECRET_ACCESS_KEY'],
      region: "ap-northeast-1",
    )
    local_file_path = '/myapp/images/' + file_name
    s3resoruce.bucket(ENV['S3_BUCKETS_NAME']).object(file_name).upload_file(local_file_path)
    File.delete(local_file_path)
    file_name
  end

  def get_object_url(file_name)
    s3resoruce = Aws::S3::Resource.new(
      access_key_id: ENV['ACCESS_KEY_ID'],
      secret_access_key: ENV['SECRET_ACCESS_KEY'],
      region: "ap-northeast-1",
    )
    signer = Aws::S3::Presigner.new(client: s3resoruce.client)
    presigned_url = signer.presigned_url(:get_object,
                                         bucket: ENV['S3_BUCKETS_NAME'], key: file_name, expires_in: 360000)
  end

  # S3にアップロードした画像を削除する
  def object_delete(file_name)
    s3resoruce = Aws::S3::Resource.new(
      access_key_id: ENV['ACCESS_KEY_ID'],
      secret_access_key: ENV['SECRET_ACCESS_KEY'],
      region: "ap-northeast-1",
    )
    s3resoruce.bucket(ENV['S3_BUCKETS_NAME']).object(file_name).delete
  end

  # omiaiにPOSTする
  def html_post(url, header_length, data)
    api_headers = {
      'accept' => '*/*',
      'Content-type' => 'application/x-www-form-urlencoded; charset=utf-8',
      'accept-encoding' => 'gzip;q=1.0, compress;q=0.5',
      'User-agent' => 'Omiai/9.3.6 (iPhone; iOS 14.4; Scale/2.0)',
      'accept-language' => 'ja-JP;q=1.0',
      'content-length' => header_length
    }
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.path)
    req.set_form_data(data)
    req.initialize_http_header(api_headers)
    res = http.request(req)
    p res
    res
  end

  def get_results(token)
    # 新規順を開く
    sleep rand(10..20)
    params_fresh = { omi_access_token: token.token, action_code: 'view', screen_code: 'search_fresh' }
    html_post("https://api2.omiai-jp.com/logging/action", "95", params_fresh)
    # おすすめ順を開く
    sleep rand(10..20)
    params_search = { omi_access_token: token.token, action_code: 'view', screen_code: 'search' }
    html_post("https://api2.omiai-jp.com/logging/action", "89", params_search)
    # ログイン順を一度リフレッシュ
    sleep rand(10..20)
    params_refresh = { omi_access_token: token.token, limit: '48' }
    html_post("https://api2.omiai-jp.com/search/sort/login", "62", params_refresh)
    # ログイン順の結果を取得
    sleep rand(10..20)
    params_recommend = { omi_access_token: token.token, limit: '48', offset: '1' }
    html_post('https://api2.omiai-jp.com/search/sort/login/results', "69", params_recommend)
  end
end