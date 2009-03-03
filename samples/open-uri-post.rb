# From: http://d.hatena.ne.jp/urekat/20070201/1170349097
require "open-uri"
require "net/http"

module Net
  class HTTPRequest
    self.class_eval{
      attr_reader :postdata
      def initialize(path, initheader = nil)
        klass = initheader["postdata"] ? HTTP::Post : HTTP::Get if initheader
        @postdata = initheader.delete("postdata")
        super klass::METHOD,
              klass::REQUEST_HAS_BODY,
              klass::RESPONSE_HAS_BODY,
              path, initheader
      end
    }
  end
  class HTTP
    self.class_eval{
      alias :_request :request
      def request(req, body = nil, &block)
        body = req.postdata if req.respond_to?(:postdata)
        _request(req, body, &block)
      end
    }
  end
end
