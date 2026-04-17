defmodule StellarDAG.GraphDB do
  # alias Boltx.Sips, as: Boltx

  def upsert_job(job) do
    query = """
    MERGE (j:Job {id: $id})
    SET j.name = $name,
        j.namespace = $namespace,
        j.image = $image,
        j.status = $status,
        j.x = $x,
        j.y = $y
    """

    Boltx.query!(Bolt, query, %{
      "id" => job.id,
      "name" => job.name,
      "namespace" => job.namespace,
      "image" => job.image,
      "status" => job.status,
      "x" => job.x || 180,
      "y" => job.y || 100
    })

    Enum.each(job.predecessors || [], fn pred_id ->
      add_dependency(job.id, pred_id)
    end)
  end
  
  def add_dependency(job_id, predecessor_id) do
    query = """
    MATCH (a:Job {id: $job_id}), (b:Job {id: $predecessor_id})
    MERGE (a)-[:DEPENDS_ON]->(b)
    """

    Boltx.query!(Bolt, query, %{"job_id" => job_id, "predecessor_id" => predecessor_id})
  end

  def remove_dependency(job_id, predecessor_id) do
    query = """
    MATCH (a:Job {id: $job_id})-[r:DEPENDS_ON]->(b:Job {id: $predecessor_id})
    DELETE r
    """

    Boltx.query!(Bolt, query, %{"job_id" => job_id, "predecessor_id" => predecessor_id})
  end
end
