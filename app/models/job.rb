# frozen_string_literal: true

# == Schema Information
#
# Table name: jobs
#
#  id              :bigint(8)        not null, primary key
#  title           :string           not null
#  description     :text             not null
#  requirements    :text
#  location        :string
#  salary_range    :string
#  deadline        :datetime
#  status          :string           default("open"), not null
#  organization_id :bigint(8)        not null
#  user_id         :bigint(8)        not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  job_type        :string           default("full_time")
#  job_category    :string    
#  contact_email   :string
#  views_count     :integer          default(0)
#  application_count :integer       default(0)

class Job < ApplicationRecord
  include Paginable

  # Constants
  STATUS_TYPES = %w(open closed archived).freeze
  JOB_TYPES = %w(full_time part_time internship contract remote).freeze
  TITLE_LENGTH_LIMIT = 100
  DESCRIPTION_LENGTH_LIMIT = 5000
  REQUIREMENTS_LENGTH_LIMIT = 2000

  # Validations
  validates :title, presence: true, length: { maximum: TITLE_LENGTH_LIMIT }
  validates :description, presence: true, length: { maximum: DESCRIPTION_LENGTH_LIMIT }
  validates :requirements, length: { maximum: REQUIREMENTS_LENGTH_LIMIT }, if: -> { requirements.present? }
  validates :status, inclusion: { in: STATUS_TYPES }
  validates :job_type, inclusion: { in: JOB_TYPES }
  validates :contact_email, email_address: true, if: -> { contact_email.present? }
  validate :validate_organization_can_post_job
  validate :validate_deadline

  # Associations
  belongs_to :organization
  belongs_to :user
  has_many :job_applications, dependent: :destroy
  has_many :applicants, through: :job_applications, source: :user

  # Scopes
  scope :open, -> { where(status: 'open') }
  scope :closed, -> { where(status: 'closed') }
  scope :archived, -> { where(status: 'archived') }
  scope :active, -> { where(status: %w(open closed)) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_organization, ->(org_id) { where(organization_id: org_id) }
  scope :by_job_type, ->(job_type) { where(job_type: job_type) if job_type.present? }
  scope :by_query, ->(query) {
    where('title ILIKE :q OR description ILIKE :q', q: "%#{query}%") if query.present?
  }
  scope :deadline_approaching, -> {
    where('deadline IS NOT NULL AND deadline > ? AND deadline < ?', Time.now, 7.days.from_now)
  }

  # Callbacks
  before_validation :set_default_status, on: :create
  before_validation :set_default_contact_email, on: :create
  # after_create :notify_organization_members
  # after_update :notify_status_change, if: :saved_change_to_status?

  # Instance methods
  def open?
    status == 'open'
  end

  def closed?
    status == 'closed'
  end

  def archived?
    status == 'archived'
  end

  def close!
    update(status: 'closed')
  end

  def archive!
    update(status: 'archived')
  end

  def reopen!
    update(status: 'open')
  end

  def deadline_passed?
    deadline.present? && deadline < Time.now
  end

  def increment_views!
    increment!(:views_count)
  end

  def applied_by?(user)
    job_applications.where(user_id: user.id).exists?
  end

  def saved_by?(user)
    return false unless user.present?
    saved_jobs = user.saved_jobs || []
    saved_jobs.include?(id.to_s)
  end

  def to_param
    id.to_s
  end

  private

  def validate_organization_can_post_job
    if organization.blank?
      errors.add(:organization, I18n.t('jobs.errors.organization_required'))
    end
  end

  def validate_deadline
    if deadline.present? && deadline < Time.now
      errors.add(:deadline, I18n.t('jobs.errors.deadline_past'))
    end
  end

  def set_default_status
    self.status ||= 'open'
  end

  def set_default_contact_email
    self.contact_email ||= user.email
  end

  # def notify_organization_members
  #   OrganizationMailer.new_job_posted(self).deliver_later
  # end

  # def notify_status_change
  #   if status_previously_changed?(from: 'open', to: 'closed')
  #     # Notify applicants that the job was closed
  #     job_applications.each do |application|
  #       JobMailer.job_closed_notification(application).deliver_later
  #     end
  #   end
  # end
end