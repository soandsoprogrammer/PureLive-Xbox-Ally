use std::{collections::BTreeMap, time::Duration};

#[derive(serde::Deserialize)]
pub struct StreamInput {
    pub url: String,
    pub headers: BTreeMap<String, String>,
}

impl StreamInput {
    pub fn agent(&self) -> ureq::Agent {
        let timeout = Some(Duration::from_secs(7));
        ureq::Agent::config_builder()
            .proxy(None)
            .timeout_connect(timeout)
            .timeout_recv_response(timeout)
            .timeout_per_read(timeout)
            .build()
            .into()
    }

    pub fn request(
        &self,
        agent: &ureq::Agent,
        target: &str,
    ) -> ureq::RequestBuilder<ureq::typestate::WithoutBody> {
        let mut request = agent.get(target);
        let same_origin = url::Url::parse(target)
            .ok()
            .zip(url::Url::parse(&self.url).ok())
            .is_some_and(|(target, source)| target.origin() == source.origin());
        for (name, value) in &self.headers {
            let sensitive = matches!(
                name.to_ascii_lowercase().as_str(),
                "cookie" | "authorization" | "proxy-authorization"
            );
            if same_origin || !sensitive {
                request = request.header(name.as_str(), value.as_str());
            }
        }
        request
    }
}
