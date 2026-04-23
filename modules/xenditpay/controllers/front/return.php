<?php
class XenditpayReturnModuleFrontController extends ModuleFrontController
{
    public function initContent()
    {
        parent::initContent();

        $id_cart = (int)Tools::getValue('id_cart');
        $id_module = (int)Tools::getValue('id_module');
        $id_order = (int)Tools::getValue('id_order');
        $key = Tools::getValue('key');

        if (!$id_order || !$id_module || !$key) {
            $this->errors[] = $this->module->l('Invalid return from Xendit.');
            $this->redirectWithNotifications('index.php?controller=order');
            return;
        }

        // Redirect to standard PrestaShop order confirmation page
        $url = 'index.php?controller=order-confirmation&id_cart=' . $id_cart . '&id_module=' . $id_module . '&id_order=' . $id_order . '&key=' . $key;
        Tools::redirect($url);
    }
}
