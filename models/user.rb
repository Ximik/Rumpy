class User < ActiveRecord::Base
  validate_uniqueness_of :jid
end
