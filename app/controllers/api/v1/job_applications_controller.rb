# frozen_string_literal: true

class Api::V1::JobApplicationsController < Api::BaseController
  include Authorization

  before_action -> { authorize_if_got_token! :read, :'read:applications' }, except: [:create, :update, :withdraw]
  before_action -> { doorkeeper_authorize! :write, :'write:applications' }, only: [:create, :update, :withdraw]
  before_action :require_user!
  before_action :set_job, only: [:create, :index_by_job]
  before_action :set_application, only: [:show, :update, :withdraw]
  before_action :check_can_apply, only: [:create]
  before_action :check_application_ownership, only: [:withdraw]
  before_action :check_job_ownership, only: [:index_by_job, :update]

  def index
    if current_user.organization?
      # Organization users see applications to their jobs
      @applications = JobApplication.joins(:job)
                       .where(jobs: { organization_id: current_user.organization_id })
                       .includes(:user, :job)
                       .recent
                       .page(params[:page])
                       .per(15)
    else
      # Regular users see their own applications
      @applications = JobApplication.by_user(current_user.id)
                       .includes(:job)
                       .recent
                       .page(params[:page])
                       .per(15)
    end

    render json: @applications, each_serializer: REST::JobApplicationSerializer
  end

  def show
    if owner_or_job_poster?
      render json: @application, serializer: REST::JobApplicationSerializer::Detailed
    else
      render json: { error: I18n.t('job_applications.errors.not_authorized') }, status: :forbidden
    end
  end

  def create
    @application = JobApplication.new(application_params)
    @application.user = current_user
    @application.job = @job

    if @application.save
      render json: @application, serializer: REST::JobApplicationSerializer::Detailed, status: :created
    else
      render json: { error: @application.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    # Only job posters can update application status
    unless current_user.organization_id == @application.job.organization_id
      render json: { error: I18n.t('job_applications.errors.not_authorized') }, status: :forbidden
      return
    end

    if @application.update(status_params)
      render json: @application, serializer: REST::JobApplicationSerializer::Detailed
    else
      render json: { error: @application.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def withdraw
    if @application.withdraw!
      render json: @application, serializer: REST::JobApplicationSerializer::Detailed
    else
      render json: { error: @application.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def index_by_job
    @applications = @job.job_applications
                    .includes(:user)
                    .recent
                    .page(params[:page])
                    .per(15)

    render json: @applications, each_serializer: REST::JobApplicationSerializer
  end

  private

  def set_job
    @job = Job.find(params[:job_id])
  end

  def set_application
    @application = JobApplication.find(params[:id])
  end

  def application_params
    params.permit(:cover_letter, :resume, :applicant_email, :applicant_phone_number, :applicant_fullname)
  end

  def status_params
    params.permit(:status, :notes)
  end

  def check_can_apply
    unless current_user.can_apply_job?
      render json: { error: I18n.t('job_applications.errors.cannot_apply') }, status: :forbidden
    end
  end

  def check_application_ownership
    unless current_user.id == @application.user_id
      render json: { error: I18n.t('job_applications.errors.not_authorized') }, status: :forbidden
    end
  end

  def check_job_ownership
    unless current_user.organization_id == @job.aa
      render json: { error: I18n.t('job_applications.errors.not_authorized') }, status: :forbidden
    end
  end

  def owner_or_job_poster?
    current_user.id == @application.user_id || 
    (current_user.organization? && current_user.organization_id == @application.job.organization_id)
  end
end