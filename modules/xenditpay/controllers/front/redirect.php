<?php
class XenditpayRedirectModuleFrontController extends ModuleFrontController
{
    public function postProcess()
    {
        $cart = $this->context->cart;
        if ($cart->id_customer == 0 || $cart->id_address_delivery == 0 || $cart->id_address_invoice == 0 || !$this->module->active) {
            Tools::redirect('index.php?controller=order&step=1');
        }

        $customer = new Customer($cart->id_customer);
        if (!Validate::isLoadedObject($customer)) {
            Tools::redirect('index.php?controller=order&step=1');
        }

        $currency = $this->context->currency;
        $total = (float)$cart->getOrderTotal(true, Cart::BOTH);
        
        // We will validate the order right away as Awaiting Xendit Payment
        $mailVars = array();
        $orderStatus = Configuration::get('XENDIT_OS_AWAITING');

        $this->module->validateOrder(
            $cart->id,
            $orderStatus,
            $total,
            $this->module->displayName,
            null,
            $mailVars,
            (int)$currency->id,
            false,
            $customer->secure_key
        );

        $orderId = $this->module->currentOrder;
        $order = new Order($orderId);

        // Call Xendit API to create Invoice
        $secretKey = Configuration::get('XENDIT_SECRET_KEY');
        $invoiceUrl = $this->createXenditInvoice($order, $customer, $total, $currency, $secretKey);

        if ($invoiceUrl) {
            Tools::redirect($invoiceUrl);
        } else {
            // Error creating invoice, redirect back to order with error
            $this->errors[] = $this->module->l('Failed to create payment invoice. Please try again.');
            $this->redirectWithNotifications('index.php?controller=order');
        }
    }

    private function createXenditInvoice($order, $customer, $total, $currency, $secretKey)
    {
        $externalId = 'ps_order_' . $order->id . '_' . time();
        $returnUrl = $this->context->link->getModuleLink($this->module->name, 'return', array('id_cart' => $order->id_cart, 'id_module' => $this->module->id, 'id_order' => $order->id, 'key' => $customer->secure_key));

        $data = array(
            'external_id' => $externalId,
            'amount' => $total,
            'payer_email' => $customer->email,
            'description' => 'Payment for Order #' . $order->reference,
            'success_redirect_url' => $returnUrl,
            'failure_redirect_url' => $this->context->link->getPageLink('order'),
            'currency' => $currency->iso_code
        );

        $ch = curl_init('https://api.xendit.co/v2/invoices');
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_USERPWD, $secretKey . ':');
        curl_setopt($ch, CURLOPT_HTTPHEADER, array('Content-Type: application/json'));
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode == 200) {
            $responseData = json_decode($response, true);
            if (isset($responseData['invoice_url'])) {
                return $responseData['invoice_url'];
            }
        }
        
        PrestaShopLogger::addLog('Xendit Invoice Creation Failed: ' . $response, 3, $httpCode, 'Order', $order->id);
        return false;
    }
}
