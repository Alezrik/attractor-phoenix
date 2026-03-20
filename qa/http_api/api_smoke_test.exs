defmodule AttractorEx.APISmokeTest do
  use AttractorEx.APISmokeCase, async: false

  test "GET /pipelines returns an empty list for a fresh server", %{base_url: base_url} do
    response = Req.get!("#{base_url}/pipelines")

    assert response.status == 200
    assert response.body == %{"pipelines" => []}
  end
end
