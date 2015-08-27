class Chapter < ActiveRecord::Base
  has_many :sections, :dependent => :destroy
  has_many :paragraphs, :through => :sections

  has_paper_trail
end
