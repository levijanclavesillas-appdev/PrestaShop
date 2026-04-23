<?php
class XenditpayWebhookModuleFrontController extends ModuleFrontController
{
    public function postProcess()
    {
        // Read input
        $payload = file_get_contents('php://input');
        $headers = getallheaders();

        $webhookToken = Configuration::get('XENDIT_WEBHOOK_TOKEN');
        $xenditToken = isset($headers['x-callback-token']) ? $headers['x-callback-token'] : '';

        // Validate token if configured
        if (!empty($webhookToken) && $webhookToken !== $xenditToken) {
            PrestaShopLogger::addLog('Xendit Webhook failed: Invalid callback token', 3);
            http_response_code(403);
            die('Forbidden');
        }

        $data = json_decode($payload, true);
        if (!$data || !isset($data['external_id']) || !isset($data['status'])) {
            http_response_code(400);
            die('Bad Request');
        }

        $externalId = $data['external_id'];
        $status = $data['status'];

        // Extract Order ID from external_id (format: ps_order_{id}_{time})
        if (preg_match('/^ps_order_(\d+)_/', $externalId, $matches)) {
            $orderId = (int)$matches[1];
            $order = new Order($orderId);

            if (Validate::isLoadedObject($order)) {
                $history = new OrderHistory();
                $history->id_order = $order->id;

                if ($status === 'PAID') {
                    // Update to Payment Accepted
                    $paymentAcceptedState = Configuration::get('PS_OS_PAYMENT');
                    if ($order->current_state != $paymentAcceptedState) {
                        $history->changeIdOrderState((int)$paymentAcceptedState, $order->id);
                        $history->addWithemail();
                    }
                } elseif ($status === 'EXPIRED') {
                    // Update to Canceled
                    $canceledState = Configuration::get('PS_OS_CANCELED');
                    if ($order->current_state != $canceledState) {
                        $history->changeIdOrderState((int)$canceledState, $order->id);
                        $history->addWithemail();
                    }
                }
            } else {
                PrestaShopLogger::addLog('Xendit Webhook: Order not found ' . $orderId, 2);
            }
        }

        http_response_code(200);
        die('OK');
    }
}
