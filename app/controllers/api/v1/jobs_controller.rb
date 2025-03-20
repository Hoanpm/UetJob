# frozen_string_literal: true

class Api::V1::JobsController < Api::BaseController
  include Authorization

  before_action -> { authorize_if_got_token! :read, :'read:jobs' }, except: [:create, :update, :destroy, :save_job, :unsave_job]
  before_action -> { doorkeeper_authorize! :write, :'write:jobs' }, only: [:create, :update, :destroy, :save_job, :unsave_job]
  before_action :require_user!, except: [:index, :show]
  before_action :set_job, only: [:show, :update, :destroy, :save_job, :unsave_job]
  before_action :check_job_ownership, only: [:update, :destroy]
  before_action :check_can_post_job, only: [:create]
  before_action :check_can_save_job, only: [:save_job, :unsave_job]

  def index
    @jobs = filtered_jobs.page(params[:page]).per(15)
    render json: @jobs, each_serializer: REST::JobSerializer
  end

  def show
    @job.increment_views! unless current_user&.id == @job.user_id
    render json: @job, serializer: REST::JobSerializer::Detailed
  end

  def create
    @job = Job.new(job_params)
    @job.user = current_user
    @job.organization = current_user.organization

    if @job.save
      render json: @job, serializer: REST::JobSerializer::Detailed, status: :created
    else
      render json: { error: @job.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @job.update(job_params)
      render json: @job, serializer: REST::JobSerializer::Detailed
    else
      render json: { error: @job.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    if @job.destroy
      render json: { success: true }, status: :ok
    else
      render json: { error: @job.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def my_jobs
    @jobs = Job.by_organization(current_user.organization_id).active.recent.page(params[:page]).per(15)
    render json: @jobs, each_serializer: REST::JobSerializer
  end

  def saved_jobs
    return render json: [], status: :ok unless current_user.saved_jobs.present?
    
    job_ids = current_user.saved_jobs
    @jobs = Job.where(id: job_ids).active.recent.page(params[:page]).per(15)
    render json: @jobs, each_serializer: REST::JobSerializer
  end

  def save_job
    saved_jobs = current_user.saved_jobs || []
    
    unless saved_jobs.include?(@job.id.to_s)
      saved_jobs << @job.id.to_s
      current_user.update(saved_jobs: saved_jobs)
    end
    
    render json: { success: true }, status: :ok
  end

  def unsave_job
    saved_jobs = current_user.saved_jobs || []
    
    if saved_jobs.include?(@job.id.to_s)
      saved_jobs.delete(@job.id.to_s)
      current_user.update(saved_jobs: saved_jobs)
    end
    
    render json: { success: true }, status: :ok
  end

  private

  def set_job
    @job = Job.find(params[:id])
  end

  def job_params
    params.permit(:title, :description, :requirements, :location, 
                  :salary_range, :deadline, :status, :job_type, :contact_email, :job_category)
  end

  def filtered_jobs
    jobs = Job.active.includes(:organization, :user)
    
    # Apply filters
    jobs = jobs.by_organization(params[:organization_id]) if params[:organization_id].present?
    jobs = jobs.by_job_type(params[:job_type]) if params[:job_type].present?
    jobs = jobs.by_query(params[:q]) if params[:q].present?
    
    # Sort options
    case params[:sort]
    when 'newest'
      jobs = jobs.order(created_at: :desc)
    when 'oldest'
      jobs = jobs.order(created_at: :asc)
    when 'deadline'
      jobs = jobs.order('deadline IS NULL, deadline ASC')
    else
      jobs = jobs.order(created_at: :desc)
    end
    
    jobs
  end

  def check_job_ownership
    unless current_user.organization_id == @job.organization_id
      render json: { error: I18n.t('jobs.errors.not_authorized') }, status: :forbidden
    end
  end

  def check_can_post_job
    unless current_user.can_post_job?
      render json: { error: I18n.t('jobs.errors.cannot_post') }, status: :forbidden
    end
  end

  def check_can_save_job
    unless current_user.can_seek_job?
      render json: { error: I18n.t('jobs.errors.cannot_save') }, status: :forbidden
    end
  end
end